// app/lib/widgets/permissions_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../util/file_mode.dart';

/// chmod dialog: a 9-checkbox rwx grid (owner/group/others) two-way synced
/// with an octal text field. Returns `(mode, recursive)` via Navigator.pop,
/// or null when cancelled. Special bits (setuid/setgid/sticky) survive a
/// checkbox-only edit; the octal field accepts 4-digit values to set them.
///
/// [initialMode] may be null when the current permissions are unknown (the
/// listing omitted them and a stat fallback failed): the dialog then shows a
/// warning and keeps Apply disabled until the user sets a mode explicitly —
/// never silently offering `chmod 000`.
class PermissionsDialog extends StatefulWidget {
  final String entryName;
  final int? initialMode;
  final bool isDirectory;

  const PermissionsDialog({
    super.key,
    required this.entryName,
    required this.initialMode,
    required this.isDirectory,
  });

  @override
  State<PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<PermissionsDialog> {
  late int _mode = (widget.initialMode ?? 0) & 0xFFF;
  late final TextEditingController _octalCtrl = TextEditingController(
      text: widget.initialMode == null ? '' : modeToOctal(_mode));
  bool _recursive = false;

  /// Whether the user has set a mode themselves (checkbox or valid octal).
  /// Gates Apply when [PermissionsDialog.initialMode] is unknown.
  bool _touched = false;

  // (row label, read bit, write bit, execute bit) per permission class.
  static const _rows = [
    ('Owner', kModeUserRead, kModeUserWrite, kModeUserExecute),
    ('Group', kModeGroupRead, kModeGroupWrite, kModeGroupExecute),
    ('Others', kModeOtherRead, kModeOtherWrite, kModeOtherExecute),
  ];
  // Key suffixes per row for widget tests: perm_u_r, perm_g_w, perm_o_x...
  static const _rowKeys = ['u', 'g', 'o'];

  /// Apply is allowed only when the octal field holds a complete valid mode
  /// (so a half-typed '64' or stale invalid text can never be submitted) and,
  /// for unknown initial permissions, the user has explicitly set one.
  bool get _canApply =>
      parseOctal(_octalCtrl.text) != null &&
      (widget.initialMode != null || _touched);

  void _setBit(int bit, bool on) {
    setState(() {
      _touched = true;
      _mode = on ? (_mode | bit) : (_mode & ~bit);
      final text = modeToOctal(_mode);
      // Only rewrite when the text actually changed, and keep the caret at
      // the end — a plain `.text =` would clobber the selection even when
      // nothing changed.
      if (_octalCtrl.text != text) {
        _octalCtrl.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
  }

  void _onOctalChanged(String text) {
    setState(() {
      final parsed = parseOctal(text);
      if (parsed != null) {
        _mode = parsed;
        _touched = true;
      }
      // Invalid/partial text keeps the last valid mode; Apply is disabled
      // via _canApply until the field parses again.
    });
  }

  @override
  void dispose() {
    _octalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final octalInvalid =
        _octalCtrl.text.isNotEmpty && parseOctal(_octalCtrl.text) == null;
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Permissions — ${widget.entryName}',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.initialMode == null) ...[
            const Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: AppColors.orange),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Current permissions unknown — set them before applying.',
                  style: TextStyle(color: AppColors.orange, fontSize: 11),
                ),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {0: FixedColumnWidth(64)},
            children: [
              const TableRow(children: [
                SizedBox.shrink(),
                Text('Read',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Write',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Execute',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ]),
              for (final (i, row) in _rows.indexed)
                TableRow(children: [
                  Text(row.$1,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12)),
                  for (final (j, bit) in [row.$2, row.$3, row.$4].indexed)
                    Checkbox(
                      key: Key('perm_${_rowKeys[i]}_${'rwx'[j]}'),
                      value: _mode & bit != 0,
                      onChanged: (v) => _setBit(bit, v ?? false),
                      side: const BorderSide(color: Color(0xFF444444)),
                      activeColor: AppColors.accent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Octal',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _octalCtrl,
                onChanged: _onOctalChanged,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-7]')),
                  LengthLimitingTextInputFormatter(4),
                ],
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  isDense: true,
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: octalInvalid
                              ? AppColors.red
                              : AppColors.border)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: octalInvalid
                              ? AppColors.red
                              : AppColors.accent)),
                ),
              ),
            ),
            if (octalInvalid) ...[
              const SizedBox(width: 8),
              const Text('3–4 octal digits',
                  style: TextStyle(color: AppColors.red, fontSize: 10)),
            ],
          ]),
          if (widget.isDirectory) ...[
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(
                key: const Key('perm_recursive'),
                value: _recursive,
                onChanged: (v) => setState(() => _recursive = v ?? false),
                side: const BorderSide(color: Color(0xFF444444)),
                activeColor: AppColors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const Text('Apply recursively',
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 12)),
            ]),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _canApply
              ? () =>
                  Navigator.pop(context, (mode: _mode, recursive: _recursive))
              : null,
          child: Text('Apply',
              style: TextStyle(
                  color: _canApply
                      ? AppColors.accent
                      : AppColors.textTertiary)),
        ),
      ],
    );
  }
}
