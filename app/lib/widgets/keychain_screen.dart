import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/ssh_key.dart';
import '../providers/key_provider.dart';
import '../services/key_gen_service.dart';
import '../theme/app_theme.dart';
import 'deploy_key_dialog.dart';
import 'ys_form_controls.dart';

import 'package:yourssh_ui/yourssh_ui.dart';

class KeychainScreen extends StatefulWidget {
  /// Test seam: a fake overrides the ssh-keygen probe and generation.
  final KeyGenService? keyGen;
  const KeychainScreen({super.key, this.keyGen});

  @override
  State<KeychainScreen> createState() => _KeychainScreenState();
}

class _KeychainScreenState extends State<KeychainScreen> {
  bool _showPanel = false;
  late final KeyGenService _keyGen = widget.keyGen ?? KeyGenService();

  Future<void> _addKeyFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select SSH Private Key',
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    await context.read<KeyProvider>().addKeyFromFile(
      result.files.first.path!,
      result.files.first.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KeyProvider>();

    return Row(
      children: [
        Expanded(
          child: Container(
            color: YsColors.background,
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
                          onGenerate: () => setState(() => _showPanel = true),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: provider.keys.length,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _KeyTile(
                            key: ValueKey(provider.keys[i].id),
                            entry: provider.keys[i],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_showPanel)
          _GenerateKeyPanel(
            keyGen: _keyGen,
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
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4 + YsSpace.s1),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'SSH Keys',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: YsColors.foreground,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FButton(
            variant: .outline,
            size: .xs,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.upload),
            onPress: onAdd,
            child: const Text('Import'),
          ),
          const SizedBox(width: YsSpace.s2),
          FButton(
            variant: .primary,
            size: .xs,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.plus),
            onPress: onGenerate,
            child: const Text('Generate'),
          ),
        ],
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
  bool _focused = false;
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
    // Actions appear on hover and while one of them holds keyboard focus.
    final showActions = _hovered || _focused;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: YsSpace.s4,
            vertical: YsSpace.s3,
          ),
          decoration: BoxDecoration(
            color: showActions ? YsColors.secondary : YsColors.card,
            borderRadius: BorderRadius.circular(YsRadius.card),
            border: Border.all(color: YsColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(YsRadius.control + 2),
                ),
                child: const Icon(
                  FLucideIcons.keyRound,
                  color: AppColors.purple,
                  size: 18,
                ),
              ),
              const SizedBox(width: YsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YsColors.foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: YsSpace.s2),
                        YsTag(e.algorithmLabel),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.privateKeyPath,
                      style: const TextStyle(
                        color: YsColors.mutedForeground,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!exists)
                      const Text(
                        'File not found',
                        style: TextStyle(color: YsColors.error, fontSize: 11),
                      ),
                    const SizedBox(height: 4),
                    _CertRow(entry: e),
                  ],
                ),
              ),
              // Always built and focusable so keyboard users can Tab onto them
              // (focus reveals them). While hidden they are invisible, ignore
              // pointer input and are left out of semantics.
              IgnorePointer(
                ignoring: !showActions,
                child: ExcludeSemantics(
                  excluding: !showActions,
                  child: Opacity(
                    opacity: showActions ? 1 : 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (e.publicKey.isNotEmpty) ...[
                          SettingsIconButton(
                            icon: FLucideIcons.copy,
                            tooltip: 'Copy public key',
                            onPress: () {
                              Clipboard.setData(
                                ClipboardData(text: e.publicKey),
                              );
                              AppSnack.success(context, 'Public key copied');
                            },
                          ),
                          const SizedBox(width: 6),
                          SettingsIconButton(
                            icon: FLucideIcons.cloudUpload,
                            tooltip: 'Deploy to host…',
                            onPress: () => showYsDialog(
                              context,
                              builder: (_) => DeployKeyDialog(entry: e),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        SettingsIconButton(
                          icon: FLucideIcons.trash2,
                          tooltip: 'Remove key',
                          onPress: () => _confirmDelete(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showYsConfirm(
      context,
      title: 'Remove Key',
      message: 'Remove "${widget.entry.label}" from keychain?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok && context.mounted) {
      await context.read<KeyProvider>().deleteKey(widget.entry.id);
    }
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
          const YsStatusBadge('CERT', status: YsStatus.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              filename,
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SettingsIconButton(
            icon: FLucideIcons.unlink,
            tooltip: 'Unlink certificate',
            onPress: () =>
                context.read<KeyProvider>().removeCertificate(entry.id),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FButton(
        variant: .ghost,
        size: .xs,
        mainAxisSize: MainAxisSize.min,
        onPress: () async {
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
        child: const Text('Link certificate…'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onGenerate;
  const _EmptyState({required this.onAdd, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return YsEmptyState(
      icon: FLucideIcons.keyRound,
      title: 'No keys added',
      message: 'Keys from ~/.ssh are auto-discovered on startup',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FButton(
            variant: .outline,
            mainAxisSize: MainAxisSize.min,
            onPress: onAdd,
            child: const Text('Import Key'),
          ),
          const SizedBox(width: YsSpace.s3),
          FButton(
            variant: .primary,
            mainAxisSize: MainAxisSize.min,
            onPress: onGenerate,
            child: const Text('+ Generate Key'),
          ),
        ],
      ),
    );
  }
}

// ── Generate Key Panel ────────────────────────────────────

class _GenerateKeyPanel extends StatefulWidget {
  final VoidCallback onClose;
  final KeyGenService keyGen;
  const _GenerateKeyPanel({required this.onClose, required this.keyGen});

  @override
  State<_GenerateKeyPanel> createState() => _GenerateKeyPanelState();
}

class _GenerateKeyPanelState extends State<_GenerateKeyPanel> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'id_ed25519');
  final _passphrase = TextEditingController();
  String _type = 'ed25519';
  bool _saving = false;

  /// null while the probe runs; rsa/ecdsa options are gated on it.
  bool? _sshKeygenAvailable;

  /// Non-null switches the panel to the success state (copy + done).
  String? _generatedPublicKey;

  @override
  void initState() {
    super.initState();
    widget.keyGen.probeSshKeygen().then((ok) {
      if (mounted) setState(() => _sshKeygenAvailable = ok);
    });
  }

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
      final sshDir = Directory(p.join(docsDir.path, 'YourSSH', 'keys'));
      await sshDir.create(recursive: true);

      final name = _label.text.trim();
      final result = _type == 'ed25519'
          ? await widget.keyGen.generateEd25519(
              name: name,
              passphrase: _passphrase.text,
              dir: sshDir.path,
            )
          : await widget.keyGen.generateWithSshKeygen(
              type: _type,
              name: name,
              passphrase: _passphrase.text,
              dir: sshDir.path,
            );

      if (!mounted) return;
      final provider = context.read<KeyProvider>();
      final entry = await provider.addKeyFromFile(result.privateKeyPath, name);
      if (_passphrase.text.isNotEmpty) {
        // Saved as pp_<keyId> so the key works without re-prompting.
        await provider.savePassphrase?.call(entry.id, _passphrase.text);
      }
      if (mounted) {
        setState(() => _generatedPublicKey = result.publicKeyLine);
      }
    } catch (e) {
      if (mounted) AppSnack.error(context, 'Key generation failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(left: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _generatedPublicKey != null ? _buildSuccess() : _buildForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    final pub = _generatedPublicKey!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        YsSpace.s4,
        YsSpace.s4,
        YsSpace.s4,
        YsSpace.s5,
      ),
      children: [
        const Text(
          'Key generated. Public key:',
          style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
        ),
        const SizedBox(height: YsSpace.s2),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: YsColors.card,
            borderRadius: BorderRadius.circular(YsRadius.card),
            border: Border.all(color: YsColors.border),
          ),
          child: SelectableText(
            pub,
            style: const TextStyle(
              color: YsColors.foreground,
              fontSize: 12,
              fontFamily: kYsMonoFontFamily,
              fontFamilyFallback: kYsMonoFontFallback,
            ),
          ),
        ),
        const SizedBox(height: YsSpace.s4),
        FButton(
          variant: .primary,
          prefix: const Icon(FLucideIcons.copy),
          onPress: () {
            Clipboard.setData(ClipboardData(text: pub));
            AppSnack.success(context, 'Public key copied');
          },
          child: const Text('Copy public key'),
        ),
        const SizedBox(height: YsSpace.s2),
        FButton(
          variant: .ghost,
          onPress: widget.onClose,
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final keygenOk = _sshKeygenAvailable ?? true;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          YsSpace.s4,
          YsSpace.s4,
          YsSpace.s4,
          YsSpace.s5,
        ),
        children: [
          FTextFormField(
            key: const Key('keygen-name'),
            control: .managed(controller: _label),
            label: const Text('Key name'),
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            validator: (v) => v?.isEmpty == true ? 'Required' : null,
            // Keep the caret in the field when Enter hits an invalid form.
            onEditingComplete: _label.clearComposing,
            onSubmit: (_) => _saving ? null : _submit(),
          ),
          const SizedBox(height: YsSpace.s3),
          FSelect<String>.rich(
            key: const Key('keygen-algorithm'),
            control: .lifted(
              value: _type,
              onChange: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            format: (v) => switch (v) {
              'rsa' => 'RSA 4096',
              'ecdsa' => 'ECDSA P-256',
              _ => 'Ed25519 (recommended)',
            },
            label: const Text('Algorithm'),
            description: _sshKeygenAvailable == false
                ? const Text('RSA/ECDSA require OpenSSH client (ssh-keygen)')
                : null,
            children: [
              const FSelectItem<String>(
                title: Text('Ed25519 (recommended)'),
                value: 'ed25519',
              ),
              FSelectItem<String>(
                title: const Text('RSA 4096'),
                value: 'rsa',
                enabled: keygenOk,
              ),
              FSelectItem<String>(
                title: const Text('ECDSA P-256'),
                value: 'ecdsa',
                enabled: keygenOk,
              ),
            ],
          ),
          const SizedBox(height: YsSpace.s3),
          FTextFormField.password(
            key: const Key('keygen-passphrase'),
            control: .managed(controller: _passphrase),
            label: const Text('Passphrase (optional)'),
            description: const Text('Leave empty for no passphrase'),
            autofillHints: const [],
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _saving ? null : _submit(),
          ),
          const SizedBox(height: YsSpace.s5),
          FButton(
            variant: .primary,
            onPress: _saving ? null : _submit,
            child: _saving
                ? const FCircularProgress(size: .sm)
                : const Text('Generate Key'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Generate SSH Key',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: YsColors.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SettingsIconButton(
            icon: FLucideIcons.x,
            tooltip: 'Close',
            onPress: widget.onClose,
          ),
        ],
      ),
    );
  }
}
