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

import 'package:yourssh_ui/yourssh_ui.dart';

/// Keys tab — list of SSH keys with Generate / Import actions.
class MobileKeysScreen extends StatelessWidget {
  const MobileKeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;
    final hosts = context.watch<HostProvider>().allHosts;

    // Count how many hosts reference each key.
    int usageFor(String keyId) => hosts.where((h) => h.keyId == keyId).length;

    final inUseCount = keys.where((k) => usageFor(k.id) > 0).length;

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (FHeader adds its own top safe area) ───────────────────
          FHeader(
            title: const Text('Keys'),
            suffixes: [
              Tooltip(
                message: 'Generate key',
                excludeFromSemantics: true,
                child: FHeaderAction(
                  key: const ValueKey('keys-generate-action'),
                  icon: const Icon(FLucideIcons.plus),
                  semanticsLabel: 'Generate key',
                  onPress: () => _showGenerateDialog(context),
                ),
              ),
              Tooltip(
                message: 'Import key',
                excludeFromSemantics: true,
                child: FHeaderAction(
                  key: const ValueKey('keys-import-action'),
                  icon: const Icon(FLucideIcons.fileUp),
                  semanticsLabel: 'Import key',
                  onPress: () => _importKey(context),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MobileTokens.space4,
              0,
              MobileTokens.space4,
              MobileTokens.space2,
            ),
            child: Text(
              '${keys.length} ${keys.length == 1 ? 'key' : 'keys'}'
              ' · $inUseCount in use',
              style: mobileBody(size: 13, color: MobileColors.textMuted),
            ),
          ),

          // ── Key list ───────────────────────────────────────────────────────
          Expanded(
            child: keys.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: MobileTokens.space4 * 4,
                    ),
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

          // ── Bottom action buttons ──────────────────────────────────────────
          _BottomActions(
            onGenerate: () => _showGenerateDialog(context),
            onImport: () => _importKey(context),
          ),
        ],
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
    final passphrase = await _showPassphraseSheet(
      context,
      result.files.first.name,
    );
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
    BuildContext context,
    String filename,
  ) async {
    return showFSheet<String>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: null,
      builder: (ctx) => _ImportPassphraseSheet(filename: filename),
    );
  }

  void _showGenerateDialog(BuildContext context) {
    showFSheet<void>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: null,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<KeyProvider>(),
        child: Provider.value(
          value: context.read<KeyGenService>(),
          child: const _GenerateSheet(),
        ),
      ),
    );
  }

  Future<void> _showKeyActions(BuildContext context, SshKeyEntry entry) async {
    await showFSheet<void>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: null,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(MobileTokens.space2),
          child: FItem(
            key: const ValueKey('key-remove-item'),
            variant: .destructive,
            prefix: const Icon(FLucideIcons.trash2),
            title: const Text('Remove key'),
            onPress: () {
              Navigator.pop(ctx);
              _confirmDelete(context, entry);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SshKeyEntry entry) async {
    final ok = await showYsDialog<bool>(
      context,
      builder: (ctx) => YsDialog(
        title: 'Remove "${entry.label}"?',
        body: const Text(
          'This removes the key from the keychain. The file on disk is kept.',
        ),
        actions: [
          FButton(
            autofocus: true,
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FButton(
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
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
    final available = await context.read<KeyGenService>().probeSshKeygen();
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
      const _AlgoOption('ed25519', 'Ed25519', 'Fast, modern, recommended'),
      if (_sshKeygenAvailable) ...[
        const _AlgoOption('rsa', 'RSA 4096', 'Widely compatible'),
        const _AlgoOption('ecdsa', 'ECDSA P-256', 'Elliptic curve'),
      ],
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MobileTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Generate Key', style: mobileHeading(size: 18)),
            const SizedBox(height: MobileTokens.space3),

            // ── Algorithm picker ────────────────────────────────────────────
            Wrap(
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
            const SizedBox(height: MobileTokens.space3),

            // ── Name field ──────────────────────────────────────────────────
            FTextField(
              key: const ValueKey('keygen-name'),
              control: FTextFieldControl.managed(controller: _nameCtrl),
              label: const Text('Key name'),
              hint: 'e.g. id_ed25519',
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: MobileTokens.space3),

            // ── Passphrase field (stays obscured) ───────────────────────────
            FTextField(
              key: const ValueKey('keygen-passphrase'),
              control: FTextFieldControl.managed(controller: _passphraseCtrl),
              label: const Text('Passphrase (optional)'),
              hint: 'Leave empty for none',
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),

            if (_error != null) ...[
              const SizedBox(height: MobileTokens.space2),
              Text(
                _error!,
                style: mobileBody(size: 13, color: MobileColors.red),
              ),
            ],

            const SizedBox(height: MobileTokens.space4),

            // ── Generate button ─────────────────────────────────────────────
            FButton(
              onPress: _loading ? null : _generate,
              child: _loading
                  ? const FCircularProgress()
                  : const Text('Generate'),
            ),
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

  const _BottomActions({required this.onGenerate, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MobileColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(MobileTokens.space3),
          child: Row(
            children: [
              Expanded(
                child: FButton(
                  onPress: onGenerate,
                  child: const Text('Generate'),
                ),
              ),
              const SizedBox(width: MobileTokens.space3),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: onImport,
                  child: const Text('Import'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            FLucideIcons.keyRound,
            size: 48,
            color: MobileColors.textFaint,
          ),
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
    return FTappable.static(
      onPress: onTap,
      semanticsLabel: option.label,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: MobileTokens.touchTarget),
        child: Container(
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
            mainAxisSize: MainAxisSize.min,
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
                style: mobileBody(size: 11, color: MobileColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Import passphrase sheet ───────────────────────────────────────────────────

/// Sheet that asks for an optional passphrase before importing a key.
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
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MobileTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Import Key', style: mobileHeading(size: 18)),
            const SizedBox(height: MobileTokens.space1),
            Text(
              widget.filename,
              style: mobileBody(size: 13, color: MobileColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: MobileTokens.space3),
            FTextField(
              key: const ValueKey('keyimport-passphrase'),
              control: FTextFieldControl.managed(controller: _ctrl),
              label: const Text('Passphrase (optional)'),
              hint: 'Leave empty if the key is unencrypted',
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: MobileTokens.space4),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.pop(context, null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: MobileTokens.space3),
                Expanded(
                  child: FButton(
                    onPress: () => Navigator.pop(context, _ctrl.text),
                    child: const Text('Import'),
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
