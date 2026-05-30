import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

enum CommandType { action, navSection, host, snippet }

class CommandItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final CommandType type;
  final VoidCallback execute;

  const CommandItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
    required this.execute,
  });
}

// ---------------------------------------------------------------------------
// Searcher
// ---------------------------------------------------------------------------

class CommandPaletteSearcher {
  CommandPaletteSearcher._();

  static int score(String query, String target) {
    if (query.isEmpty) return 1;
    final q = query.toLowerCase();
    final t = target.toLowerCase();

    // Acronym match: each query char matches a word-initial char in target.
    // "pd" → p from "prod", d from "db" in "prod-db" → acronym match.
    // This scores higher than a plain subsequence match.
    final acronym = _acronymScore(q, t);
    if (acronym > 0) return acronym + 10;

    // Fallback: greedy subsequence scoring with consecutive bonus.
    int qi = 0;
    int s = 0;
    int consecutive = 0;
    for (int ti = 0; ti < t.length && qi < q.length; ti++) {
      if (t[ti] == q[qi]) {
        int bonus = 1 + consecutive * 2;
        if (ti == qi) bonus += 2; // prefix bonus
        s += bonus;
        consecutive++;
        qi++;
      } else {
        consecutive = 0;
      }
    }
    return qi == q.length ? s : 0;
  }

  static int _acronymScore(String query, String target) {
    final wordStarts = <int>[];
    for (int i = 0; i < target.length; i++) {
      if (i == 0 || _isSeparator(target[i - 1])) wordStarts.add(i);
    }
    int qi = 0;
    int s = 0;
    for (final pos in wordStarts) {
      if (qi >= query.length) break;
      if (target[pos] == query[qi]) {
        s += 5;
        qi++;
      }
    }
    return qi == query.length ? s : 0;
  }

  static bool _isSeparator(String c) =>
      c == '-' || c == '_' || c == '.' || c == '/' || c == ' ';

  static List<CommandItem> search(String query, List<CommandItem> items) {
    if (query.isEmpty) return items;
    final scored = <({CommandItem item, int score})>[];
    for (final item in items) {
      final s = score(query, item.title);
      if (s > 0) scored.add((item: item, score: s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((r) => r.item).toList();
  }

  static List<(String, bool)> highlightSpans(String query, String text) {
    if (query.isEmpty) return [(text, false)];
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    final result = <(String, bool)>[];
    int qi = 0;
    int lastEnd = 0;
    for (int ti = 0; ti < t.length && qi < q.length; ti++) {
      if (t[ti] == q[qi]) {
        if (ti > lastEnd) result.add((text.substring(lastEnd, ti), false));
        result.add((text.substring(ti, ti + 1), true));
        lastEnd = ti + 1;
        qi++;
      }
    }
    if (lastEnd < text.length) result.add((text.substring(lastEnd), false));
    return result;
  }
}

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

class CommandPaletteDialog extends StatefulWidget {
  final List<CommandItem> items;

  const CommandPaletteDialog({super.key, required this.items});

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _selectedIndex = 0;
  List<CommandItem> _results = [];

  static const _itemHeight = 44.0;

  @override
  void initState() {
    super.initState();
    _results = widget.items;
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {
      _selectedIndex = 0;
      _results = CommandPaletteSearcher.search(_controller.text, widget.items);
    });
  }

  void _executeSelected() {
    if (_results.isEmpty || !mounted) return;
    final fn = _results[_selectedIndex].execute;
    Navigator.of(context).pop();
    fn();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final offset = (_selectedIndex * _itemHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(offset);
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        setState(() => _selectedIndex = min(_selectedIndex + 1, _results.length - 1));
        _scrollToSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _selectedIndex = max(_selectedIndex - 1, 0));
        _scrollToSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _executeSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Focus(
          onKeyEvent: _onKeyEvent,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sidebar,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SearchField(
                  controller: _controller,
                  onSubmitted: (_) => _executeSelected(),
                ),
                if (_results.isNotEmpty) ...[
                  const Divider(height: 1, color: AppColors.border),
                  Flexible(
                    child: ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _results.length,
                      itemExtent: _itemHeight,
                      itemBuilder: (_, i) => _CommandRow(
                        item: _results[i],
                        query: _controller.text,
                        selected: i == _selectedIndex,
                        onTap: () {
                          final fn = _results[i].execute;
                          Navigator.of(context).pop();
                          fn();
                        },
                        onHover: () => setState(() => _selectedIndex = i),
                      ),
                    ),
                  ),
                ],
                const _HintBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _SearchField({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: onSubmitted,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search hosts, actions, snippets...',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  final CommandItem item;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _CommandRow({
    required this.item,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: _CommandPaletteDialogState._itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 15,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: item.title,
                      query: query,
                      selected: selected,
                    ),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _TypeBadge(type: item.type),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final bool selected;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final spans = CommandPaletteSearcher.highlightSpans(query, text);
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: spans
            .map((s) => TextSpan(
                  text: s.$1,
                  style: TextStyle(
                    color: s.$2 ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: s.$2 ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final CommandType type;

  const _TypeBadge({required this.type});

  static const _labels = {
    CommandType.host: 'host',
    CommandType.navSection: 'nav',
    CommandType.snippet: 'snippet',
    CommandType.action: 'action',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        _labels[type] ?? '',
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
      ),
    );
  }
}

class _HintBar extends StatelessWidget {
  const _HintBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: const Row(
        children: [
          _HintChip('↑↓', 'navigate'),
          SizedBox(width: 12),
          _HintChip('↵', 'execute'),
          SizedBox(width: 12),
          _HintChip('esc', 'close'),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final String keyLabel;
  final String description;

  const _HintChip(this.keyLabel, this.description);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            keyLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          description,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
        ),
      ],
    );
  }
}
