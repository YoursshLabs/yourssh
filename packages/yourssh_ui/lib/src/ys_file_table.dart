import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// Height of a [YsFileTable] row and of its header.
const double kYsFileTableRowHeight = 28;

/// Background of a selected [YsFileTable] row (amber at 14%).
const Color kYsFileTableSelectedColor = Color(0x24F3A231);

/// Background of a hovered, unselected [YsFileTable] row.
const Color kYsFileTableHoverColor = Color(0x8026231F);

/// Width of the checkbox column when [YsFileTable.checkboxes] is on.
const double _kCheckboxColumnWidth = 32;

/// Sort state of a [YsFileTable]: a column id and a direction.
@immutable
class YsSort {
  const YsSort(this.column, {this.ascending = true});

  /// [YsColumn.id] of the sorted column.
  final String column;
  final bool ascending;

  /// The sort after the header of [column] is pressed: the same column flips
  /// direction, another column starts ascending.
  YsSort next(String column) => column == this.column
      ? YsSort(column, ascending: !ascending)
      : YsSort(column);

  @override
  bool operator ==(Object other) =>
      other is YsSort && other.column == column && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(column, ascending);

  @override
  String toString() => 'YsSort($column, ${ascending ? 'asc' : 'desc'})';
}

/// One column of a [YsFileTable].
@immutable
class YsColumn<T> {
  const YsColumn({
    required this.id,
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.sortable = false,
    this.numeric = false,
    this.minTableWidth = 0,
  });

  /// Stable id, used by [YsSort].
  final String id;

  /// Header text.
  final String label;

  /// Builds the cell for a row. It must depend only on the row (and on
  /// inherited widgets): the table reuses a row's widgets until that row's
  /// selection or cursor state changes.
  final Widget Function(BuildContext context, T row) cell;

  /// Fixed width; null shares the remaining width by [flex].
  final double? width;
  final int flex;

  /// Whether pressing the header calls [YsFileTable.onSort].
  final bool sortable;

  /// Right-aligns the header and the cells (sizes, counts).
  final bool numeric;

  /// The column is hidden while the table is narrower than this.
  final double minTableWidth;
}

/// The SFTP file list: a header of sortable columns over lazily built
/// 28 px rows, with mouse and keyboard selection.
///
/// The table holds no selection or sort state of its own: it reports
/// gestures and the caller updates [selected] / [sort] and the order of
/// [rows] (already sorted and filtered, in display order).
///
/// Mouse: a click selects the row (`onSelect(row)`), Cmd/Ctrl-click adds or
/// removes it (`additive`), Shift-click selects the range from the last
/// anchor (`range`), a double click opens it; with [openOnTap] a plain click
/// opens instead. A right-click reports the row and the pointer's global
/// position to [onContextMenu] without changing the selection.
///
/// Keyboard (while the table has focus): Up/Down move the cursor row
/// (Shift extends the selection to it), Space toggles the cursor row,
/// Enter opens it, Cmd/Ctrl+A selects all, Shift+F10 or the menu key opens
/// the context menu at the cursor row.
///
/// Only visible rows are built, and a rebuild of the table rebuilds only the
/// rows whose selected/cursor state changed, as long as the same [columns]
/// list is passed again.
class YsFileTable<T extends Object> extends StatefulWidget {
  const YsFileTable({
    super.key,
    required this.rows,
    required this.columns,
    this.selected = const {},
    this.onSelect,
    this.onOpen,
    this.onContextMenu,
    this.sort,
    this.onSort,
    this.onSelectAll,
    this.checkboxes = false,
    this.openOnTap = false,
    this.draggable = false,
    this.rowLabel,
    this.dragFeedback,
    this.selectAllKey,
    this.focusNode,
    this.autofocus = false,
    this.controller,
  });

  /// The rows in display order.
  final List<T> rows;
  final List<YsColumn<T>> columns;
  final Set<T> selected;
  final void Function(T row, {bool additive, bool range})? onSelect;
  final void Function(T row)? onOpen;

  /// Right-click (or Shift+F10 / menu key) on a row, with the global
  /// position to open a menu at.
  final void Function(T row, Offset globalPosition)? onContextMenu;
  final YsSort? sort;
  final void Function(YsSort sort)? onSort;

  /// Select-all checkbox and Cmd/Ctrl+A: true selects every row, false
  /// clears the selection.
  final ValueChanged<bool>? onSelectAll;

  /// Adds a checkbox column (rows toggle with `additive`, the header
  /// selects all).
  final bool checkboxes;

  /// A plain click opens the row instead of selecting it.
  final bool openOnTap;

  /// Rows are [Draggable]s carrying the row value.
  final bool draggable;

  /// Accessible name of a row (checkbox label, drag chip).
  final String Function(T row)? rowLabel;
  final Widget Function(T row)? dragFeedback;
  final Key? selectAllKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final ScrollController? controller;

  @override
  State<YsFileTable<T>> createState() => _YsFileTableState<T>();
}

class _RowCache<T> {
  _RowCache(
    this.widget,
    this.index,
    this.selected,
    this.cursor,
    this.focused,
    this.generation,
  );
  final Widget widget;
  final int index;
  final bool selected;
  final bool cursor;
  final bool focused;
  final int generation;
}

class _YsFileTableState<T extends Object> extends State<YsFileTable<T>> {
  static const _maxCachedRows = 512;

  FocusNode? _ownFocus;
  ScrollController? _ownScroll;
  FocusNode get _focus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'YsFileTable'));
  ScrollController get _scroll =>
      widget.controller ?? (_ownScroll ??= ScrollController());

  int _cursor = -1;
  bool _focused = false;

  Timer? _clickTimer;
  int _lastClickIndex = -1;

  final Map<T, _RowCache<T>> _cache = HashMap<T, _RowCache<T>>();
  int _generation = 0;
  List<YsColumn<T>> _visible = const [];

  @override
  void didUpdateWidget(YsFileTable<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.columns, widget.columns) ||
        old.checkboxes != widget.checkboxes ||
        old.draggable != widget.draggable) {
      _invalidate();
    }
    if (!identical(old.rows, widget.rows) &&
        !listEquals(old.rows, widget.rows)) {
      // Keep the cursor on the same row when it is still listed (re-sort,
      // filter); a new listing has no cursor until the next arrow key.
      final cursorRow = _cursor >= 0 && _cursor < old.rows.length
          ? old.rows[_cursor]
          : null;
      _cursor = cursorRow == null ? -1 : widget.rows.indexOf(cursorRow);
      _lastClickIndex = -1;
      _cache.clear();
    }
  }

  @override
  void dispose() {
    _clickTimer?.cancel();
    _ownFocus?.dispose();
    _ownScroll?.dispose();
    super.dispose();
  }

  void _invalidate() {
    _generation++;
    _cache.clear();
  }

  // ── Gestures ──────────────────────────────────────────

  void _setCursor(int index) {
    if (_cursor == index) return;
    setState(() => _cursor = index);
  }

  void _handleTap(int index) {
    if (index >= widget.rows.length) return;
    final row = widget.rows[index];
    _focus.requestFocus();
    final keys = HardwareKeyboard.instance;
    final additive = keys.isMetaPressed || keys.isControlPressed;
    final range = keys.isShiftPressed;
    final isDoubleClick =
        (_clickTimer?.isActive ?? false) && _lastClickIndex == index;
    _clickTimer?.cancel();
    _lastClickIndex = -1;
    _setCursor(index);

    if (additive || range) {
      widget.onSelect?.call(row, additive: additive, range: range);
    } else if (widget.openOnTap || isDoubleClick) {
      widget.onOpen?.call(row);
    } else {
      _lastClickIndex = index;
      _clickTimer = Timer(kDoubleTapTimeout, () {});
      widget.onSelect?.call(row);
    }
  }

  void _handleSecondaryTap(int index, Offset globalPosition) {
    if (index >= widget.rows.length) return;
    _focus.requestFocus();
    _setCursor(index);
    widget.onContextMenu?.call(widget.rows[index], globalPosition);
  }

  void _handleCheckbox(int index) {
    if (index >= widget.rows.length) return;
    _setCursor(index);
    widget.onSelect?.call(widget.rows[index], additive: true);
  }

  // ── Keyboard ──────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = widget.rows;
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (rows.isEmpty) return KeyEventResult.handled;
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final next = _cursor < 0 ? 0 : (_cursor + step).clamp(0, rows.length - 1);
      _setCursor(next);
      _ensureVisible(next);
      if (keys.isShiftPressed) widget.onSelect?.call(rows[next], range: true);
      return KeyEventResult.handled;
    }

    final hasCursor = _cursor >= 0 && _cursor < rows.length;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!hasCursor) return KeyEventResult.ignored;
      if (!repeat) widget.onOpen?.call(rows[_cursor]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (!hasCursor) return KeyEventResult.ignored;
      if (!repeat) widget.onSelect?.call(rows[_cursor], additive: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA &&
        (keys.isMetaPressed || keys.isControlPressed)) {
      if (widget.onSelectAll == null) return KeyEventResult.ignored;
      if (!repeat) widget.onSelectAll!(true);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.f10 && keys.isShiftPressed) ||
        key == LogicalKeyboardKey.contextMenu) {
      if (!hasCursor || widget.onContextMenu == null) {
        return KeyEventResult.ignored;
      }
      if (!repeat) {
        widget.onContextMenu!(rows[_cursor], _cursorAnchor(_cursor));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Global point at the bottom-left of row [index] (keyboard menus).
  Offset _cursorAnchor(int index) {
    final box = context.findRenderObject() as RenderBox?;
    final offset = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    final local = Offset(
      YsSpace.s4,
      kYsFileTableRowHeight * (index + 2) - offset,
    );
    return box == null ? local : box.localToGlobal(local);
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = index * kYsFileTableRowHeight;
    final bottom = top + kYsFileTableRowHeight;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  // ── Build ─────────────────────────────────────────────

  Widget _row(BuildContext context, int index) {
    final row = widget.rows[index];
    final selected = widget.selected.contains(row);
    final cursor = index == _cursor;
    final focused = cursor && _focused;
    final cached = _cache[row];
    if (cached != null &&
        cached.index == index &&
        cached.selected == selected &&
        cached.cursor == cursor &&
        cached.focused == focused &&
        cached.generation == _generation) {
      return cached.widget;
    }
    final built = _YsFileRow<T>(
      key: ValueKey('ys-file-row-$index'),
      table: this,
      row: row,
      index: index,
      selected: selected,
      focused: focused,
      columns: _visible,
    );
    if (_cache.length >= _maxCachedRows) _cache.clear();
    _cache[row] = _RowCache(
      built,
      index,
      selected,
      cursor,
      focused,
      _generation,
    );
    return built;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      key: const ValueKey('ys-file-table-focus'),
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 13, color: YsColors.foreground),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visible = [
              for (final c in widget.columns)
                if (constraints.maxWidth >= c.minTableWidth) c,
            ];
            if (!listEquals(visible, _visible)) {
              _visible = visible;
              _invalidate();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _YsFileTableHeader<T>(
                  columns: visible,
                  sort: widget.sort,
                  onSort: widget.onSort,
                  checkbox: widget.checkboxes
                      ? FCheckbox(
                          key: widget.selectAllKey,
                          semanticsLabel: 'Select all',
                          value: _allSelected,
                          onChange: widget.onSelectAll == null
                              ? null
                              : (_) => widget.onSelectAll!(!_allSelected),
                        )
                      : null,
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemExtent: kYsFileTableRowHeight,
                    itemCount: widget.rows.length,
                    itemBuilder: _row,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _allSelected =>
      widget.rows.isNotEmpty && widget.rows.every(widget.selected.contains);
}

/// Lays out one cell of [column] with the table's padding and alignment.
Widget _cell<T>(YsColumn<T> column, Widget child) {
  final aligned = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Align(
      alignment: column.numeric
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: child,
    ),
  );
  final width = column.width;
  return width != null
      ? SizedBox(width: width, child: aligned)
      : Expanded(flex: column.flex, child: aligned);
}

class _YsFileTableHeader<T> extends StatelessWidget {
  const _YsFileTableHeader({
    required this.columns,
    required this.sort,
    required this.onSort,
    required this.checkbox,
  });

  final List<YsColumn<T>> columns;
  final YsSort? sort;
  final void Function(YsSort)? onSort;
  final Widget? checkbox;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kYsFileTableRowHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: YsColors.mutedForeground,
        ),
        child: Row(
          children: [
            if (checkbox != null)
              SizedBox(
                width: _kCheckboxColumnWidth,
                child: Center(child: checkbox),
              )
            else
              const SizedBox(width: YsSpace.s1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: YsSpace.s1),
                child: Row(
                  children: [for (final c in columns) _cell(c, _label(c))],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(YsColumn<T> column) {
    final sorted = sort?.column == column.id;
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(column.label)),
        if (sorted) ...[
          const SizedBox(width: 2),
          Icon(
            sort!.ascending ? FLucideIcons.arrowUp : FLucideIcons.arrowDown,
            size: 12,
            color: YsColors.foreground,
          ),
        ],
      ],
    );
    final onSort = this.onSort;
    if (!column.sortable || onSort == null) return text;
    return FTappable.static(
      semanticsLabel: 'Sort by ${column.label}',
      onPress: () => onSort(sort?.next(column.id) ?? YsSort(column.id)),
      child: text,
    );
  }
}

class _YsFileRow<T extends Object> extends StatelessWidget {
  const _YsFileRow({
    super.key,
    required this.table,
    required this.row,
    required this.index,
    required this.selected,
    required this.focused,
    required this.columns,
  });

  final _YsFileTableState<T> table;
  final T row;
  final int index;
  final bool selected;
  final bool focused;
  final List<YsColumn<T>> columns;

  @override
  Widget build(BuildContext context) {
    final widget = table.widget;
    final label = widget.rowLabel?.call(row);
    Widget content = Row(
      children: [
        if (widget.checkboxes)
          SizedBox(
            width: _kCheckboxColumnWidth,
            // Outside the row's tap detector so a checkbox click never also
            // selects-only or opens; not a Tab stop (Space toggles the row).
            child: Center(
              child: ExcludeFocus(
                child: FCheckbox(
                  semanticsLabel: label == null ? null : 'Select $label',
                  value: selected,
                  onChange: (_) => table._handleCheckbox(index),
                ),
              ),
            ),
          )
        else
          const SizedBox(width: YsSpace.s1),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (_) => table._handleTap(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: YsSpace.s1),
              child: Row(
                children: [
                  for (final c in columns) _cell(c, c.cell(context, row)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    // Right-click anywhere on the row, the checkbox included.
    content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) =>
          table._handleSecondaryTap(index, d.globalPosition),
      child: content,
    );
    content = _RowSurface(selected: selected, focused: focused, child: content);
    if (widget.draggable) {
      content = Draggable<T>(
        data: row,
        feedback:
            widget.dragFeedback?.call(row) ?? _DragChip(label: label ?? '$row'),
        child: content,
      );
    }
    return Semantics(
      container: true,
      selected: selected,
      label: label,
      child: content,
    );
  }
}

/// Row background: selected tint, hover tint, and the cursor outline while
/// the table has focus. Hover state is local so hovering rebuilds one row.
class _RowSurface extends StatefulWidget {
  const _RowSurface({
    required this.selected,
    required this.focused,
    required this.child,
  });

  final bool selected;
  final bool focused;
  final Widget child;

  @override
  State<_RowSurface> createState() => _RowSurfaceState();
}

class _RowSurfaceState extends State<_RowSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? kYsFileTableSelectedColor
        : _hovered
        ? kYsFileTableHoverColor
        : const Color(0x00000000);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        key: const ValueKey('ys-file-row-surface'),
        decoration: BoxDecoration(
          color: color,
          border: widget.focused
              ? Border.all(color: YsColors.primary.withValues(alpha: 0.6))
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Default drag feedback: the row label in an amber chip.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: kYsFontFamily,
        fontSize: 13,
        color: YsColors.accentText,
        decoration: TextDecoration.none,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s3,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: YsColors.card,
          border: Border.all(color: YsColors.primary.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(YsRadius.control),
        ),
        child: Text(label),
      ),
    );
  }
}
