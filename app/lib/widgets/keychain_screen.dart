import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/ssh_key.dart';
import '../providers/key_provider.dart';
import '../theme/app_theme.dart';

class KeychainScreen extends StatelessWidget {
  const KeychainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KeyProvider>();

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _TopBar(
            onAdd: () => _addKeyFromFile(context),
            onGenerate: () => _showGenerateDialog(context),
          ),
          Expanded(
            child: provider.keys.isEmpty
                ? _EmptyState(
                    onAdd: () => _addKeyFromFile(context),
                    onGenerate: () => _showGenerateDialog(context),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: provider.keys.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _KeyTile(key: ValueKey(provider.keys[i].id), entry: provider.keys[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addKeyFromFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select SSH Private Key',
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;
    await context.read<KeyProvider>().addKeyFromFile(result.files.first.path!, result.files.first.name);
  }

  Future<void> _showGenerateDialog(BuildContext context) async {
    final result = await showDialog<({String label, String type, String passphrase})>(
      context: context,
      builder: (_) => const _GenerateKeyDialog(),
    );
    if (result == null || !context.mounted) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(docsDir.path, 'YourSSH', 'keys'));
      await sshDir.create(recursive: true);

      final safeName = result.label.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final keyPath = p.join(sshDir.path, safeName);

      final args = [
        '-t', result.type,
        '-f', keyPath,
        '-C', result.label,
        '-N', result.passphrase,
      ];
      final proc = await Process.run('ssh-keygen', args);

      if (proc.exitCode == 0 && context.mounted) {
        await context.read<KeyProvider>().addKeyFromFile(keyPath, result.label);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Key generated: $keyPath'), backgroundColor: AppColors.accent),
          );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${proc.stderr}'), backgroundColor: AppColors.red),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red),
        );
      }
    }
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
          const Text('SSH Keys', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          _OutlinedBtn(label: 'IMPORT', icon: Icons.upload_file, onTap: onAdd),
          const SizedBox(width: 8),
          _GreenBtn(label: 'GENERATE', icon: Icons.add, onTap: onGenerate),
        ],
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlinedBtn({required this.label, required this.icon, required this.onTap});

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
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.3)),
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
  const _GreenBtn({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.black),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
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

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final exists = File(e.privateKeyPath).existsSync();

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
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.vpn_key, color: AppColors.purple, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(e.label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      _Badge(e.algorithmLabel),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.privateKeyPath,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!exists)
                    const Text('File not found', style: TextStyle(color: AppColors.red, fontSize: 11)),
                ],
              ),
            ),
            if (_hovered)
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.delete_outlined, size: 14, color: AppColors.red),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.red)),
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
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
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
            const Icon(Icons.vpn_key_outlined, size: 52, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No keys added', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Keys from ~/.ssh are auto-discovered on startup', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Import Key', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onGenerate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                    child: const Text('+ Generate Key', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13)),
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

class _GenerateKeyDialog extends StatefulWidget {
  const _GenerateKeyDialog();

  @override
  State<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends State<_GenerateKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'id_ed25519');
  final _passphrase = TextEditingController();
  String _type = 'ed25519';

  @override
  void dispose() {
    _label.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate SSH Key'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Key name', border: OutlineInputBorder()),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Algorithm', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'ed25519', child: Text('Ed25519 (recommended)')),
                  DropdownMenuItem(value: 'rsa', child: Text('RSA 4096')),
                  DropdownMenuItem(value: 'ecdsa', child: Text('ECDSA')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphrase,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passphrase (optional)',
                  border: OutlineInputBorder(),
                  helperText: 'Leave empty for no passphrase',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((
              label: _label.text.trim(),
              type: _type,
              passphrase: _passphrase.text,
            ));
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }
}
