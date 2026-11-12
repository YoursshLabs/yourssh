import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Chrome shared by the two SFTP file panels ([SftpPanel] and
/// [LocalFilePanel]): header, filter bar, path bar, footer, the name dialog,
/// and the row icon/format helpers used by their file tables.

/// Below this panel width the header's Filter and Actions drop their labels
/// (tooltips keep them).
const double kFilePanelCompactWidth = 300;

/// One entry of a panel's Actions menu.
class FilePanelAction {
  const FilePanelAction(
    this.label,
    this.icon,
    this.onPress, {
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPress;
  final bool enabled;
  final bool destructive;
}

/// Icon-only ghost button with a tooltip (the tooltip is also its
/// accessible name).
class FilePanelIconButton extends StatelessWidget {
  const FilePanelIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPress,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: FButton.icon(
      variant: .ghost,
      size: .xs,
      semanticsLabel: tooltip,
      onPress: onPress,
      child: Icon(icon),
    ),
  );
}

/// Header row: the source chip (or a static label when the panel cannot
/// switch source), an optional [badge], then Filter and Actions against the
/// right edge.
class FilePanelHeader extends StatelessWidget {
  const FilePanelHeader({
    super.key,
    required this.sourceIcon,
    required this.sourceLabel,
    this.onChangeSource,
    this.badge,
    required this.filterActive,
    required this.onToggleFilter,
    required this.actions,
  });

  final IconData sourceIcon;
  final String sourceLabel;

  /// Opens the source picker; null shows the source as a plain label.
  final VoidCallback? onChangeSource;
  final Widget? badge;
  final bool filterActive;
  final VoidCallback onToggleFilter;
  final List<FilePanelAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < kFilePanelCompactWidth;
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: YsColors.border)),
          ),
          child: Row(
            children: [
              // The source group owns all free space so Filter/Actions always
              // hug the right edge; the chip itself ellipsizes a long label.
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: _source()),
                    if (badge != null) ...[
                      const SizedBox(width: YsSpace.s1),
                      badge!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: YsSpace.s2),
              _filterButton(compact),
              const SizedBox(width: 6),
              _actionsMenu(compact),
            ],
          ),
        );
      },
    );
  }

  Widget _source() {
    final label = Text(
      sourceLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final onChange = onChangeSource;
    if (onChange == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sourceIcon, size: 14, color: YsColors.mutedForeground),
          const SizedBox(width: 6),
          Flexible(
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                color: YsColors.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              child: label,
            ),
          ),
        ],
      );
    }
    return FButton(
      variant: .outline,
      size: .xs,
      mainAxisSize: MainAxisSize.min,
      onPress: onChange,
      prefix: Icon(sourceIcon, color: YsColors.accentText),
      suffix: const Icon(FLucideIcons.chevronsUpDown),
      child: Flexible(
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: YsColors.accentText),
          child: label,
        ),
      ),
    );
  }

  Widget _filterButton(bool compact) {
    final color = filterActive ? YsColors.accentText : null;
    if (compact) {
      return Tooltip(
        message: 'Filter',
        excludeFromSemantics: true,
        child: FButton.icon(
          variant: .outline,
          size: .xs,
          selected: filterActive,
          semanticsLabel: 'Filter',
          onPress: onToggleFilter,
          child: Icon(FLucideIcons.listFilter, color: color),
        ),
      );
    }
    return FButton(
      variant: .outline,
      size: .xs,
      selected: filterActive,
      mainAxisSize: MainAxisSize.min,
      onPress: onToggleFilter,
      child: Text('Filter', style: TextStyle(color: color)),
    );
  }

  Widget _actionsMenu(bool compact) {
    return FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (final a in actions)
              FItem(
                variant: a.destructive ? .destructive : .primary,
                enabled: a.enabled,
                prefix: Icon(a.icon),
                title: Text(a.label),
                onPress: a.enabled
                    ? () {
                        controller.hide();
                        a.onPress();
                      }
                    : null,
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => compact
          ? Tooltip(
              message: 'Actions',
              excludeFromSemantics: true,
              child: FButton.icon(
                variant: .outline,
                size: .xs,
                semanticsLabel: 'Actions',
                onPress: controller.toggle,
                child: const Icon(FLucideIcons.ellipsis),
              ),
            )
          : FButton(
              variant: .outline,
              size: .xs,
              mainAxisSize: MainAxisSize.min,
              onPress: controller.toggle,
              suffix: const Icon(FLucideIcons.chevronDown),
              child: const Text('Actions'),
            ),
    );
  }
}

/// "Filter by name…" field shown under the header while filtering.
class FilePanelFilterBar extends StatelessWidget {
  const FilePanelFilterBar({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      YsSpace.s3,
      YsSpace.s2,
      YsSpace.s3,
      YsSpace.s2,
    ),
    child: FTextField(
      key: const Key('file-panel-filter'),
      autofocus: true,
      size: .sm,
      hint: 'Filter by name…',
      control: FTextFieldControl.managed(onChange: (v) => onChanged(v.text)),
      prefixBuilder: (context, style, variants) => FTextField.prefixIconBuilder(
        context,
        style,
        variants,
        const Icon(FLucideIcons.search),
      ),
    ),
  );
}

/// Back / Forward, the breadcrumb, and Refresh.
class FilePanelPathBar extends StatelessWidget {
  const FilePanelPathBar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
    required this.breadcrumb,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onRefresh;
  final Widget breadcrumb;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: YsSpace.s1),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: YsColors.border)),
    ),
    child: Row(
      children: [
        FilePanelIconButton(
          icon: FLucideIcons.chevronLeft,
          tooltip: 'Back',
          onPress: canGoBack ? onBack : null,
        ),
        FilePanelIconButton(
          icon: FLucideIcons.chevronRight,
          tooltip: 'Forward',
          onPress: canGoForward ? onForward : null,
        ),
        const SizedBox(width: 2),
        // The breadcrumb gets the remaining row width.
        Expanded(child: breadcrumb),
        FilePanelIconButton(
          icon: FLucideIcons.refreshCw,
          tooltip: 'Refresh',
          onPress: onRefresh,
        ),
      ],
    ),
  );
}

/// Item / selection count under the list.
class FilePanelFooter extends StatelessWidget {
  const FilePanelFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    alignment: AlignmentDirectional.centerStart,
    padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: YsColors.border)),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: YsColors.mutedForeground, fontSize: 11),
    ),
  );
}

/// Centered message for the list area (empty folder, no matches).
class FilePanelMessage extends StatelessWidget {
  const FilePanelMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: const TextStyle(color: YsColors.mutedForeground, fontSize: 13),
    ),
  );
}

/// Error icon + message (+ optional Retry) for the list area.
class FilePanelError extends StatelessWidget {
  const FilePanelError(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(YsSpace.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FLucideIcons.circleAlert, color: YsColors.error, size: 28),
          const SizedBox(height: YsSpace.s2),
          Text(
            message,
            style: const TextStyle(color: YsColors.error, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: YsSpace.s3),
            FButton(
              variant: .outline,
              size: .xs,
              mainAxisSize: MainAxisSize.min,
              onPress: onRetry,
              prefix: const Icon(FLucideIcons.refreshCw),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Asks for a file or folder name; pops the typed text (untrimmed) on
/// Enter or [confirmLabel], null on Cancel / dismiss.
Future<String?> showFileNameDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  required String confirmLabel,
}) => showYsDialog<String>(
  context,
  builder: (_) => _FileNameDialog(
    title: title,
    hint: hint,
    initial: initial,
    confirmLabel: confirmLabel,
  ),
);

class _FileNameDialog extends StatefulWidget {
  const _FileNameDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String? hint;
  final String initial;
  final String confirmLabel;

  @override
  State<_FileNameDialog> createState() => _FileNameDialogState();
}

class _FileNameDialogState extends State<_FileNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YsDialog(
    title: widget.title,
    body: FTextField(
      key: const Key('file-name-field'),
      control: FTextFieldControl.managed(controller: _controller),
      autofocus: true,
      hint: widget.hint,
      onSubmit: (v) => Navigator.pop(context, v),
    ),
    actions: [
      FButton(
        variant: .outline,
        onPress: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FButton(
        variant: .primary,
        onPress: () => Navigator.pop(context, _controller.text),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

// ── Row helpers ─────────────────────────────────────────────

/// Lucide icon for a listing entry.
IconData fileEntryIcon({required bool isDirectory, required String extension}) {
  if (isDirectory) return FLucideIcons.folder;
  return switch (extension) {
    'dart' ||
    'py' ||
    'js' ||
    'ts' ||
    'go' ||
    'rs' ||
    'c' ||
    'cpp' => FLucideIcons.fileCode,
    'json' || 'yaml' || 'yml' || 'toml' || 'xml' => FLucideIcons.fileBraces,
    'md' || 'txt' || 'log' => FLucideIcons.fileText,
    'sh' || 'bash' || 'zsh' => FLucideIcons.fileTerminal,
    _ => FLucideIcons.file,
  };
}

/// Name cell: type icon + ellipsized name.
class FileNameCell extends StatelessWidget {
  const FileNameCell({
    super.key,
    required this.name,
    required this.isDirectory,
    required this.extension,
  });

  final String name;
  final bool isDirectory;
  final String extension;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        fileEntryIcon(isDirectory: isDirectory, extension: extension),
        size: 15,
        color: isDirectory ? YsColors.primary : YsColors.mutedForeground,
      ),
      const SizedBox(width: YsSpace.s2),
      Expanded(child: Text(name)),
    ],
  );
}

/// Muted one-line cell text ([mono] for permissions).
class FileMetaCell extends StatelessWidget {
  const FileMetaCell(this.text, {super.key, this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: YsColors.mutedForeground,
      fontSize: mono ? 11 : 12,
      fontFamily: mono ? kYsMonoFontFamily : null,
      fontFamilyFallback: mono ? kYsMonoFontFallback : null,
    ),
  );
}

/// Clock behind the "Today" labels and [MidnightRefresh]; tests replace it.
@visibleForTesting
DateTime Function() fileDateNow = DateTime.now;

/// "Today 09:12" for today, "11/3/2026, 14:20" otherwise, "—" when unknown.
String formatEntryDate(DateTime? dt) {
  if (dt == null) return '—';
  final now = fileDateNow();
  final time =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return 'Today $time';
  }
  return '${dt.month}/${dt.day}/${dt.year}, $time';
}

/// Rebuilds a panel just after local midnight, and gives it [dayColumns] —
/// a column list kept while the day stays the same — so the file table's
/// reused rows drop their "Today" labels when the date changes.
mixin MidnightRefresh<W extends StatefulWidget> on State<W> {
  Timer? _midnight;
  DateTime? _columnsDay;
  Object? _columns;

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    final now = fileDateNow();
    final next = _dayOf(now).add(const Duration(days: 1));
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  /// [build] for today's date; the same list is returned all day.
  List<YsColumn<E>> dayColumns<E>(List<YsColumn<E>> Function() build) {
    final today = _dayOf(fileDateNow());
    if (_columns is! List<YsColumn<E>> || _columnsDay != today) {
      _columnsDay = today;
      _columns = build();
    }
    return _columns! as List<YsColumn<E>>;
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }
}

/// `drwxr-xr-x`-style permissions from a raw st_mode; "—" when unknown.
String formatEntryMode(int? mode, {required bool isDirectory}) {
  if (mode == null) return '—';
  const chars = 'rwxrwxrwx';
  final buffer = StringBuffer(isDirectory ? 'd' : '-');
  for (var i = 0; i < 9; i++) {
    buffer.write(mode & (1 << (8 - i)) != 0 ? chars[i] : '-');
  }
  return buffer.toString();
}
