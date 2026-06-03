import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

class TerminalSnippetsPanel extends StatefulWidget {
  final bool canRun;
  final ValueChanged<Snippet> onRunSnippet;
  final VoidCallback? onClose;

  const TerminalSnippetsPanel({
    super.key,
    required this.canRun,
    required this.onRunSnippet,
    this.onClose,
  });

  @override
  State<TerminalSnippetsPanel> createState() => _TerminalSnippetsPanelState();
}

class _TerminalSnippetsPanelState extends State<TerminalSnippetsPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final filtered = filterSnippets(snippets, _query);

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(left: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Column(
        children: [
          _PanelHeader(
            onSearch: (value) => setState(() => _query = value),
            onClose: widget.onClose,
          ),
          if (!widget.canRun)
            Container(
              width: double.infinity,
              color: const Color(0xFF2A1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Text(
                'No active SSH pane selected',
                style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'No snippets yet' : 'No snippets match "$_query"',
                      style: const TextStyle(color: Color(0xFF555555)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final snippet = filtered[index];
                      return _SnippetRow(
                        snippet: snippet,
                        canRun: widget.canRun,
                        onRun: () => widget.onRunSnippet(snippet),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final ValueChanged<String> onSearch;
  final VoidCallback? onClose;

  const _PanelHeader({required this.onSearch, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Snippets',
                style: TextStyle(
                  color: Color(0xFFE5E5E5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (onClose != null)
                IconButton(
                  tooltip: 'Close snippets panel',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF888888)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: onSearch,
            style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search snippets…',
              hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF555555)),
              filled: true,
              fillColor: const Color(0xFF1C1C1C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF22C55E)),
              ),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SnippetRow extends StatelessWidget {
  final Snippet snippet;
  final bool canRun;
  final VoidCallback onRun;

  const _SnippetRow({
    required this.snippet,
    required this.canRun,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snippet.label,
                  style: const TextStyle(
                    color: Color(0xFFE5E5E5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (snippet.tag.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    snippet.tag,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            snippet.command,
            style: const TextStyle(
              color: Color(0xFF22C55E),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          if (snippet.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              snippet.description,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Tooltip(
                message: 'Run snippet',
                child: TextButton.icon(
                  onPressed: canRun ? onRun : null,
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: const Text('Run'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Copy snippet',
                child: TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: snippet.command)),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
