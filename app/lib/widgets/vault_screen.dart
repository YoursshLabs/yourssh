import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../services/vault_service.dart';
import '../theme/app_theme.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _service = VaultService();
  final _localAuth = LocalAuthentication();
  bool _unlocked = false;
  bool _loading = true;
  List<VaultEntry> _entries = [];
  VaultEntry? _selected;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      if (canAuth) {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Unlock your credential vault',
          options: const AuthenticationOptions(biometricOnly: false),
        );
        if (authenticated) await _load();
        if (mounted) setState(() => _unlocked = authenticated);
      } else {
        await _load();
        if (mounted) setState(() => _unlocked = true);
      }
    } catch (_) {
      await _load();
      if (mounted) setState(() => _unlocked = true);
    }
  }

  Future<void> _load() async {
    final entries = await _service.loadAll();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  void _addEntry() {
    final labelCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('New Credential',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(labelCtrl, 'Label', 'e.g. Production DB'),
            _dialogField(userCtrl, 'Username', 'root'),
            _dialogField(passCtrl, 'Password', '••••', obscure: true),
            _dialogField(notesCtrl, 'Notes', 'Optional notes'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _service.add(VaultEntry(
                label: labelCtrl.text,
                username: userCtrl.text,
                password: passCtrl.text,
                notes: notesCtrl.text,
              ));
              await _load();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: Colors.black),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label, String hint,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: const TextStyle(color: AppColors.textTertiary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 12),
            const Text('Vault is locked',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _authenticate,
              icon: const Icon(Icons.fingerprint, size: 18),
              label: const Text('Unlock'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 240,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.sidebar,
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 14, color: AppColors.accent),
                    const SizedBox(width: 6),
                    const Text('Vault',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add,
                          size: 16, color: AppColors.accent),
                      onPressed: _addEntry,
                      tooltip: 'Add credential',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Material(
                  color: AppColors.sidebar,
                  child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.accent))
                    : _entries.isEmpty
                        ? const Center(
                            child: Text('No credentials saved',
                                style: TextStyle(
                                    color: AppColors.textTertiary)))
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (_, i) => ListTile(
                              leading: const Icon(Icons.key,
                                  size: 16, color: AppColors.textSecondary),
                              title: Text(_entries[i].label,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13)),
                              subtitle: Text(_entries[i].username,
                                  style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 11)),
                              selected: _selected?.id == _entries[i].id,
                              onTap: () => setState(() {
                                _selected = _entries[i];
                                _showPassword = false;
                              }),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 14, color: AppColors.textTertiary),
                                onPressed: () async {
                                  await _service.delete(_entries[i].id);
                                  if (_selected?.id == _entries[i].id) {
                                    setState(() => _selected = null);
                                  }
                                  await _load();
                                },
                              ),
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: _selected == null
              ? const Center(
                  child: Text('Select a credential',
                      style: TextStyle(color: AppColors.textTertiary)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selected!.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 24),
                      _detailRow('Username', _selected!.username),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _detailRow(
                              'Password',
                              _showPassword
                                  ? _selected!.password
                                  : '•' * _selected!.password.length,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy,
                                size: 16, color: AppColors.textSecondary),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _selected!.password));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Password copied'),
                                    duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                        ],
                      ),
                      if (_selected!.notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _detailRow('Notes', _selected!.notes),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        SelectableText(value,
            style: const TextStyle(
                color: AppColors.textPrimary, fontFamily: 'monospace')),
      ],
    );
  }
}
