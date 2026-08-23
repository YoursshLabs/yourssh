import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../models/ssh_key.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../services/key_gen_service.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/key_card.dart';

/// Keys tab — list of SSH keys with Generate / Import actions.
class MobileKeysScreen extends StatelessWidget {
  const MobileKeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;
    final hosts = context.watch<HostProvider>().allHosts;

    // Count how many hosts reference each key.
    int usageFor(String keyId) =>
        hosts.where((h) => h.keyId == keyId).length;

    final inUseCount =
        keys.where((k) => usageFor(k.id) > 0).length;

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space4,
                MobileTokens.space4,
                MobileTokens.space4,
                MobileTokens.space2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keys',
                          style: mobileHeading(
                              size: 30, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${keys.length} ${keys.length == 1 ? 'key' : 'keys'}'
                          ' · $inUseCount in use',
                          style: mobileBody(
                              size: 13, color: MobileColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _CircleButton(
                    icon: Icons.add,
                    onTap: () => _showGenerateDialog(context),
                  ),
                  const SizedBox(width: MobileTokens.space2),
                  _CircleButton(
                    icon: Icons.upload_file_outlined,
                    onTap: () => _importKey(context),
                  ),
                ],
              ),
            ),

            // ── Key list ─────────────────────────────────────────────────────
            Expanded(
              child: keys.isEmpty
                  ? _EmptyState(
                      onGenerate: () => _showGenerateDialog(context),
                      onImport: () => _importKey(context),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                          bottom: MobileTokens.space4 * 4),
                      itemCount: keys.length,
                      itemBuilder: (_, i) {
                        final key = keys[i];
                        return KeyCard(
                          key: ValueKey(key.id),
                          entry: key,
                          hostCount: usageFor(key.id),
                          onTap: () => _showKeyActions(context, key),
                          onLongPress: () => _showKeyActions(context, key),
                        );
                      },
                    ),
            ),

            // ── Bottom action buttons ─────────────────────────────────────────
            _BottomActions(
              onGenerate: () => _showGenerateDialog(context),
              onImport: () => _importKey(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _importKey(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select SSH Private Key',
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    if (!context.mounted) return;

    // Prompt for an optional passphrase before registering the key.
    final passphrase = await _showPassphraseSheet(context, result.files.first.name);
    if (passphrase == null) return; // user cancelled

    if (!context.mounted) return;
    final keyProv = context.read<KeyProvider>();
    final entry = await keyProv.addKeyFromFile(path, result.files.first.name);

    if (passphrase.isNotEmpty && context.mounted) {
      await keyProv.savePassphrase?.call(entry.id, passphrase);
    }
  }

  /// Shows a bottom sheet asking for an optional passphrase.
  /// Returns the passphrase string (may be empty) on Import, or `null` if
  /// the user cancelled.
  Future<String?> _showPassphraseSheet(
      BuildContext context, String filename) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobileColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ImportPassphraseSheet(filename: filename),
    );
  }

  void _showGenerateDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobileColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<KeyProvider>(),
        child: Provider.value(
          value: context.read<KeyGenService>(),
          child: const _GenerateSheet(),
        ),
      ),
    );
  }

  Future<void> _showKeyActions(
      BuildContext context, SshKeyEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MobileColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            const SizedBox(height: MobileTokens.space2),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: MobileColors.red),
              title: Text('Remove key',
                  style: mobileBody(size: 16, color: MobileColors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, entry);
              },
            ),
            const SizedBox(height: MobileTokens.space2),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, SshKeyEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MobileColors.surface,
        title: Text('Remove "${entry.label}"?',
            style: mobileHeading(size: 17)),
        content: Text(
          'This removes the key from the keychain. The file on disk is kept.',
          style: mobileBody(size: 14, color: MobileColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: mobileBody(size: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: mobileBody(size: 15, color: MobileColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<KeyProvider>().deleteKey(entry.id);
    }
  }
}

// ── Generate bottom sheet ──────────────────────────────────────────────────────

class _GenerateSheet extends StatefulWidget {
  const _GenerateSheet();

  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  final _nameCtrl = TextEditingController();
  final _passphraseCtrl = TextEditingController();
  String _algo = 'ed25519';
  bool _sshKeygenAvailable = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final available =
        await context.read<KeyGenService>().probeSshKeygen();
    if (mounted) setState(() => _sshKeygenAvailable = available);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a key name');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keyGen = context.read<KeyGenService>();
      final keyProv = context.read<KeyProvider>();
      final dir = await _keysDir();
      final GeneratedKey result;
      if (_algo == 'ed25519') {
        result = await keyGen.generateEd25519(
          name: name,
          passphrase: _passphraseCtrl.text,
          dir: dir,
        );
      } else {
        result = await keyGen.generateWithSshKeygen(
          type: _algo,
          name: name,
          passphrase: _passphraseCtrl.text,
          dir: dir,
        );
      }
      if (!mounted) return;
      final entry = await keyProv.addKeyFromFile(result.privateKeyPath, name);
      if (_passphraseCtrl.text.isNotEmpty && mounted) {
        await keyProv.savePassphrase?.call(entry.id, _passphraseCtrl.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _keysDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/YourSSH/keys');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  Widget build(BuildContext context) {
    final algoOptions = [
      const _AlgoOption('ed25519', 'Ed25519',
          'Fast, modern, recommended'),
      if (_sshKeygenAvailable) ...[
        const _AlgoOption('rsa', 'RSA 4096', 'Widely compatible'),
        const _AlgoOption('ecdsa', 'ECDSA P-256', 'Elliptic curve'),
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space4,
                MobileTokens.space3,
                MobileTokens.space4,
                0,
              ),
              child: Text('Generate Key',
                  style: mobileHeading(size: 18)),
            ),
            const SizedBox(height: MobileTokens.space3),

            // ── Algorithm picker ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4),
              child: Wrap(
                spacing: MobileTokens.space2,
                runSpacing: MobileTokens.space2,
                children: [
                  for (final opt in algoOptions)
                    _AlgoChip(
                      option: opt,
                      selected: _algo == opt.value,
                      onTap: () => setState(() => _algo = opt.value),
                    ),
                ],
              ),
            ),

            const SizedBox(height: MobileTokens.space3),

            // ── Name field ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4),
              child: _MobileField(
                controller: _nameCtrl,
                label: 'Key name',
                hint: 'e.g. id_ed25519',
              ),
            ),
            const SizedBox(height: MobileTokens.space3),

            // ── Passphrase field ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4),
              child: _MobileField(
                controller: _passphraseCtrl,
                label: 'Passphrase (optional)',
                hint: 'Leave empty for none',
                obscure: true,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: MobileTokens.space2),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: MobileTokens.space4),
                child: Text(_error!,
                    style: mobileBody(
                        size: 13, color: MobileColors.red)),
              ),
            ],

            const SizedBox(height: MobileTokens.space4),

            // ── Generate button ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4),
              child: FilledButton(
                onPressed: _loading ? null : _generate,
                style: FilledButton.styleFrom(
                  backgroundColor: MobileColors.accent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(
                      MobileTokens.touchTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MobileTokens.radiusField),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : Text('Generate',
                        style: mobileBody(
                            size: 16,
                            weight: FontWeight.w600,
                            color: Colors.black)),
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
          ],
        ),
      ),
    );
  }
}

// ── Bottom action buttons ──────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onGenerate;
  final VoidCallback onImport;

  const _BottomActions({
    required this.onGenerate,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MobileTokens.space4,
        MobileTokens.space3,
        MobileTokens.space4,
        MobileTokens.space4,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: MobileColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: onGenerate,
              style: FilledButton.styleFrom(
                backgroundColor: MobileColors.accent,
                foregroundColor: Colors.black,
                minimumSize:
                    const Size.fromHeight(MobileTokens.touchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(MobileTokens.radiusField),
                ),
              ),
              child: Text(
                'Generate',
                style: mobileBody(
                    size: 15, weight: FontWeight.w600, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(width: MobileTokens.space3),
          Expanded(
            child: OutlinedButton(
              onPressed: onImport,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: MobileColors.border),
                foregroundColor: MobileColors.textPrimary,
                minimumSize:
                    const Size.fromHeight(MobileTokens.touchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(MobileTokens.radiusField),
                ),
              ),
              child: Text(
                'Import',
                style: mobileBody(size: 15, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: MobileColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: MobileColors.border),
        ),
        child: Icon(icon, color: MobileColors.textMuted, size: 18),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onGenerate;
  final VoidCallback onImport;

  const _EmptyState({required this.onGenerate, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.vpn_key_outlined,
              size: 48, color: MobileColors.textFaint),
          const SizedBox(height: MobileTokens.space3),
          Text('No keys yet', style: mobileHeading(size: 17)),
          const SizedBox(height: MobileTokens.space1),
          Text(
            'Generate a new key or import an existing one',
            style: mobileBody(size: 13, color: MobileColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MobileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;

  const _MobileField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: mobileBody(size: 13, color: MobileColors.textMuted)),
        const SizedBox(height: MobileTokens.space1),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: mobileBody(size: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                mobileBody(size: 15, color: MobileColors.textFaint),
            filled: true,
            fillColor: MobileColors.fieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: MobileTokens.space3,
              vertical: MobileTokens.space3,
            ),
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(MobileTokens.radiusField),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(MobileTokens.radiusField),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(MobileTokens.radiusField),
              borderSide:
                  const BorderSide(color: MobileColors.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlgoOption {
  final String value;
  final String label;
  final String description;
  const _AlgoOption(this.value, this.label, this.description);
}

class _AlgoChip extends StatelessWidget {
  final _AlgoOption option;
  final bool selected;
  final VoidCallback onTap;

  const _AlgoChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: MobileTokens.space3,
          vertical: MobileTokens.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? MobileColors.accentSoft : MobileColors.surfaceAlt,
          borderRadius: BorderRadius.circular(MobileTokens.radiusField),
          border: Border.all(
            color: selected ? MobileColors.accent : MobileColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              option.label,
              style: mobileBody(
                size: 14,
                weight: FontWeight.w600,
                color: selected
                    ? MobileColors.accent
                    : MobileColors.textPrimary,
              ),
            ),
            Text(
              option.description,
              style:
                  mobileBody(size: 11, color: MobileColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sheetHandle() => Container(
      margin: const EdgeInsets.only(top: MobileTokens.space3),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: MobileColors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );

// ── Import passphrase sheet ───────────────────────────────────────────────────

/// Bottom sheet that asks for an optional passphrase before importing a key.
/// [Navigator.pop]s with the passphrase string (may be empty) on Import, or
/// `null` if the user cancels.
class _ImportPassphraseSheet extends StatefulWidget {
  final String filename;
  const _ImportPassphraseSheet({required this.filename});

  @override
  State<_ImportPassphraseSheet> createState() => _ImportPassphraseSheetState();
}

class _ImportPassphraseSheetState extends State<_ImportPassphraseSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space4,
                MobileTokens.space3,
                MobileTokens.space4,
                0,
              ),
              child: Text('Import Key', style: mobileHeading(size: 18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space4,
                MobileTokens.space1,
                MobileTokens.space4,
                0,
              ),
              child: Text(
                widget.filename,
                style: mobileBody(size: 13, color: MobileColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: MobileTokens.space3),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4),
              child: _MobileField(
                controller: _ctrl,
                label: 'Passphrase (optional)',
                hint: 'Leave empty if the key is unencrypted',
                obscure: true,
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: MobileColors.border),
                        foregroundColor: MobileColors.textPrimary,
                        minimumSize: const Size.fromHeight(
                            MobileTokens.touchTarget),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              MobileTokens.radiusField),
                        ),
                      ),
                      child: Text('Cancel',
                          style: mobileBody(
                              size: 15, weight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: MobileTokens.space3),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _ctrl.text),
                      style: FilledButton.styleFrom(
                        backgroundColor: MobileColors.accent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(
                            MobileTokens.touchTarget),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              MobileTokens.radiusField),
                        ),
                      ),
                      child: Text('Import',
                          style: mobileBody(
                              size: 15,
                              weight: FontWeight.w600,
                              color: Colors.black)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
          ],
        ),
      ),
    );
  }
}
