import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/snippet.dart';
import '../providers/snippet_provider.dart';
import '../theme/app_theme.dart';

class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final filtered = _search.isEmpty
        ? snippets
        : snippets.where((s) =>
            s.label.toLowerCase().contains(_search.toLowerCase()) ||
            s.command.toLowerCase().contains(_search.toLowerCase()) ||
            s.tag.toLowerCase().contains(_search.toLowerCase())).toList();

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _TopBar(
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            onAdd: () => _showAddDialog(context),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No snippets', style: TextStyle(color: AppColors.textTertiary)))
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _SnippetTile(snippet: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final result = await showDialog<Snippet>(
      context: context,
      builder: (_) => const _AddSnippetDialog(),
    );
    if (result != null && context.mounted) {
      await context.read<SnippetProvider>().add(result);
    }
  }
}

class _TopBar extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;
  const _TopBar({required this.search, required this.onSearch, required this.onAdd});

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
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                onChanged: onSearch,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search snippets…',
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: AppColors.textTertiary, size: 16),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: Colors.black),
                  SizedBox(width: 6),
                  Text('NEW SNIPPET', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnippetTile extends StatefulWidget {
  final Snippet snippet;
  const _SnippetTile({required this.snippet});

  @override
  State<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends State<_SnippetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.snippet;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(s.label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                      if (s.tag.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _Badge(s.tag),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.command,
                      style: const TextStyle(color: AppColors.accent, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                  if (s.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(s.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
            ),
            if (_hovered) ...[
              _ActionBtn(
                icon: Icons.copy,
                tooltip: 'Copy',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: s.command));
                },
              ),
              const SizedBox(width: 4),
              _ActionBtn(
                icon: Icons.delete_outlined,
                tooltip: 'Delete',
                color: AppColors.red,
                onTap: () => context.read<SnippetProvider>().delete(s.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.tooltip, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}

class _AddSnippetDialog extends StatefulWidget {
  const _AddSnippetDialog();

  @override
  State<_AddSnippetDialog> createState() => _AddSnippetDialogState();
}

class _AddSnippetDialogState extends State<_AddSnippetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _command = TextEditingController();
  final _description = TextEditingController();
  final _tag = TextEditingController();

  @override
  void dispose() {
    for (final c in [_label, _command, _description, _tag]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(Snippet(
      label: _label.text.trim(),
      command: _command.text.trim(),
      description: _description.text.trim(),
      tag: _tag.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Snippet'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder()),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _command,
                decoration: const InputDecoration(labelText: 'Command', border: OutlineInputBorder()),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tag,
                decoration: const InputDecoration(labelText: 'Tag (optional)', hintText: 'system, network…', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
