import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/ssh_key.dart';
import '../providers/key_provider.dart';
import '../theme/app_theme.dart';

class KeychainScreen extends StatefulWidget {
  const KeychainScreen({super.key});

  @override
  State<KeychainScreen> createState() => _KeychainScreenState();
}

class _KeychainScreenState extends State<KeychainScreen> {
  bool _showPanel = false;

  Future<void> _addKeyFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select SSH Private Key',
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    await context
        .read<KeyProvider>()
        .addKeyFromFile(result.files.first.path!, result.files.first.name);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KeyProvider>();

    return Row(
      children: [
        Expanded(
          child: Container(
            color: AppColors.bg,
            child: Column(
              children: [
                _TopBar(
                  onAdd: _addKeyFromFile,
                  onGenerate: () => setState(() => _showPanel = true),
                ),
                Expanded(
                  child: provider.keys.isEmpty
                      ? _EmptyState(
                          onAdd: _addKeyFromFile,
                          onGenerate: () =>
                              setState(() => _showPanel = true),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: provider.keys.length,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _KeyTile(
                              key: ValueKey(provider.keys[i].id),
                              entry: provider.keys[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_showPanel)
          _GenerateKeyPanel(
            onClose: () => setState(() => _showPanel = false),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onGenerate;
  const _TopBar({required this.onAdd, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text('SSH Keys',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          _OutlinedBtn(
              label: 'IMPORT', icon: Icons.upload_file, onTap: onAdd),
          const SizedBox(width: 8),
          _GreenBtn(
              label: 'GENERATE', icon: Icons.add, onTap: onGenerate),
        ],
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlinedBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

class _GreenBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GreenBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
            color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.black),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

class _KeyTile extends StatefulWidget {
  final SshKeyEntry entry;
  const _KeyTile({super.key, required this.entry});

  @override
  State<_KeyTile> createState() => _KeyTileState();
}

class _KeyTileState extends State<_KeyTile> {
  bool _hovered = false;
  bool? _exists;

  @override
  void initState() {
    super.initState();
    _checkExists();
  }

  @override
  void didUpdateWidget(_KeyTile old) {
    super.didUpdateWidget(old);
    if (old.entry.privateKeyPath != widget.entry.privateKeyPath) _checkExists();
  }

  Future<void> _checkExists() async {
    final exists = await File(widget.entry.privateKeyPath).exists();
    if (mounted && exists != _exists) setState(() => _exists = exists);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final exists = _exists ?? true; // assume OK until first probe completes

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.vpn_key,
                  color: AppColors.purple, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(e.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      _Badge(e.algorithmLabel),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.privateKeyPath,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!exists)
                    const Text('File not found',
                        style: TextStyle(
                            color: AppColors.red, fontSize: 11)),
                  const SizedBox(height: 4),
                  _CertRow(entry: e),
                ],
              ),
            ),
            if (_hovered)
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.delete_outlined,
                      size: 14, color: AppColors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Key'),
        content: Text('Remove "${widget.entry.label}" from keychain?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<KeyProvider>().deleteKey(widget.entry.id);
    }
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _CertRow extends StatelessWidget {
  final SshKeyEntry entry;
  const _CertRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.hasCertificate) {
      final filename = entry.certificatePath!.split('/').last.split('\\').last;
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('CERT',
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(filename,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
          GestureDetector(
            onTap: () => context.read<KeyProvider>().removeCertificate(entry.id),
            child: const Icon(Icons.link_off, size: 13, color: AppColors.textTertiary),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () async {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select Certificate File (*-cert.pub)',
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return;
        if (context.mounted) {
          await context.read<KeyProvider>().setCertificate(
                entry.id,
                result.files.first.path!,
              );
        }
      },
      child: const Text('Link certificate…',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onGenerate;
  const _EmptyState({required this.onAdd, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.vpn_key_outlined,
                size: 52, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No keys added',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Keys from ~/.ssh are auto-discovered on startup',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Import Key',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onGenerate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('+ Generate Key',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Generate Key Panel ────────────────────────────────────

class _GenerateKeyPanel extends StatefulWidget {
  final VoidCallback onClose;
  const _GenerateKeyPanel({required this.onClose});

  @override
  State<_GenerateKeyPanel> createState() => _GenerateKeyPanelState();
}

class _GenerateKeyPanelState extends State<_GenerateKeyPanel> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'id_ed25519');
  final _passphrase = TextEditingController();
  String _type = 'ed25519';
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final sshDir =
          Directory(p.join(docsDir.path, 'YourSSH', 'keys'));
      await sshDir.create(recursive: true);

      final safeName =
          _label.text.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final keyPath = p.join(sshDir.path, safeName);

      final proc = await Process.run('ssh-keygen', [
        '-t', _type,
        '-f', keyPath,
        '-C', _label.text.trim(),
        '-N', _passphrase.text,
      ]);

      if (!mounted) return;

      if (proc.exitCode == 0) {
        await context
            .read<KeyProvider>()
            .addKeyFromFile(keyPath, _label.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Key generated: $keyPath'),
                backgroundColor: AppColors.accent),
          );
          widget.onClose();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: ${proc.stderr}'),
              backgroundColor: AppColors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _field(_label, 'Key name',
                      autofocus: true,
                      validator: (v) =>
                          v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: _inputDecoration('Algorithm'),
                    dropdownColor: AppColors.card,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(
                          value: 'ed25519',
                          child: Text('Ed25519 (recommended)')),
                      DropdownMenuItem(
                          value: 'rsa', child: Text('RSA 4096')),
                      DropdownMenuItem(
                          value: 'ecdsa', child: Text('ECDSA')),
                    ],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passphrase,
                    obscureText: true,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    decoration: _inputDecoration(
                            'Passphrase (optional)')
                        .copyWith(
                            helperText: 'Leave empty for no passphrase',
                            helperStyle: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11)),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Text('Generate Key',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text('Generate SSH Key',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent)),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool autofocus = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      autofocus: autofocus,
      style:
          const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: _inputDecoration(label),
      validator: validator,
    );
  }
}
