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
  bool _showPanel = false;

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final filtered = _search.isEmpty
        ? snippets
        : snippets
            .where((s) =>
                s.label.toLowerCase().contains(_search.toLowerCase()) ||
                s.command.toLowerCase().contains(_search.toLowerCase()) ||
                s.tag.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Row(
      children: [
        Expanded(
          child: Container(
            color: AppColors.bg,
            child: Column(
              children: [
                _TopBar(
                  search: _search,
                  onSearch: (v) => setState(() => _search = v),
                  onAdd: () => setState(() => _showPanel = true),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No snippets',
                              style: TextStyle(color: AppColors.textTertiary)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(24),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              _SnippetTile(snippet: filtered[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_showPanel)
          _SnippetPanel(
            onClose: () => setState(() => _showPanel = false),
            onSave: (snippet) async {
              await context.read<SnippetProvider>().add(snippet);
              if (mounted) setState(() => _showPanel = false);
            },
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;
  const _TopBar(
      {required this.search, required this.onSearch, required this.onAdd});

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
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search snippets…',
                  hintStyle:
                      TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.textTertiary, size: 16),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: Colors.black),
                  SizedBox(width: 6),
                  Text('NEW SNIPPET',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3)),
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
                      Text(s.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      if (s.tag.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _Badge(s.tag),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.command,
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ),
                  if (s.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(s.description,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
            ),
            if (_hovered) ...[
              _ActionBtn(
                icon: Icons.copy,
                tooltip: 'Copy',
                onTap: () =>
                    Clipboard.setData(ClipboardData(text: s.command)),
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
  const _ActionBtn(
      {required this.icon,
      required this.tooltip,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child:
              Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
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
      decoration: BoxDecoration(
          color: AppColors.border, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    );
  }
}

// ── Snippet Panel ─────────────────────────────────────────

class _SnippetPanel extends StatefulWidget {
  final VoidCallback onClose;
  final Future<void> Function(Snippet) onSave;
  const _SnippetPanel({required this.onClose, required this.onSave});

  @override
  State<_SnippetPanel> createState() => _SnippetPanelState();
}

class _SnippetPanelState extends State<_SnippetPanel> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _command = TextEditingController();
  final _description = TextEditingController();
  final _tag = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_label, _command, _description, _tag]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(Snippet(
        label: _label.text.trim(),
        command: _command.text.trim(),
        description: _description.text.trim(),
        tag: _tag.text.trim(),
      ));
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
                  _field(_label, 'Label',
                      autofocus: true,
                      validator: (v) =>
                          v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _field(_command, 'Command',
                      maxLines: 3,
                      validator: (v) =>
                          v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _field(_description, 'Description (optional)'),
                  const SizedBox(height: 12),
                  _field(_tag, 'Tag (optional)'),
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
                          : const Text('Add Snippet',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600)),
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
            child: Text('New Snippet',
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

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool autofocus = false,
    int? maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      autofocus: autofocus,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
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
      ),
      validator: validator,
    );
  }
}
