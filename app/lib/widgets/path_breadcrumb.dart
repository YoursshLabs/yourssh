import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One clickable segment of a [PathBreadcrumb].
typedef PathCrumb = ({String label, String path});

/// Splits a POSIX [path] into crumbs with a leading root crumb.
/// Remote SFTP paths are always POSIX, regardless of the local platform.
List<PathCrumb> posixCrumbs(String path) {
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  return [
    (label: '/', path: '/'),
    for (int i = 0; i < parts.length; i++)
      (label: parts[i], path: '/${parts.sublist(0, i + 1).join('/')}'),
  ];
}

/// Horizontal, scrollable row of clickable path segments. The last crumb is
/// highlighted as the current directory. Owns no navigation logic — panels
/// supply [crumbs] and handle [onNavigate].
///
/// When [editablePath] is non-null, a trailing edit affordance lets the user
/// type an arbitrary path to jump to; the value seeds the inline editor and
/// submitting it routes through [onNavigate] just like a crumb tap.
class PathBreadcrumb extends StatefulWidget {
  final List<PathCrumb> crumbs;
  final ValueChanged<String> onNavigate;
  final String? editablePath;

  const PathBreadcrumb({
    super.key,
    required this.crumbs,
    required this.onNavigate,
    this.editablePath,
  });

  @override
  State<PathBreadcrumb> createState() => _PathBreadcrumbState();
}

class _PathBreadcrumbState extends State<PathBreadcrumb> {
  final TextEditingController _controller = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    final seed = widget.editablePath ?? '';
    _controller.text = seed;
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: seed.length);
    setState(() => _editing = true);
  }

  void _cancel() {
    if (!_editing) return;
    setState(() => _editing = false);
  }

  void _submit() {
    final value = _controller.text.trim();
    setState(() => _editing = false);
    if (value.isNotEmpty) widget.onNavigate(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) return _buildEditor();
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < widget.crumbs.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.chevron_right,
                          size: 13, color: Color(0xFF444444)),
                    ),
                  GestureDetector(
                    onTap: () => widget.onNavigate(widget.crumbs[i].path),
                    child: Text(
                      widget.crumbs[i].label,
                      style: TextStyle(
                        color: i == widget.crumbs.length - 1
                            ? const Color(0xFFD4D4D4)
                            : const Color(0xFF666666),
                        fontSize: 12,
                        fontWeight: i == widget.crumbs.length - 1
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.editablePath != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 13, color: Color(0xFF555555)),
            onPressed: _startEditing,
            tooltip: 'Go to path',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
      ],
    );
  }

  Widget _buildEditor() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: SizedBox(
        height: 28,
        child: TextField(
          controller: _controller,
          autofocus: true,
          cursorColor: const Color(0xFF22C55E),
          style: const TextStyle(
              color: Color(0xFFD4D4D4), fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            hintText: 'Enter a path and press Enter…',
            hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            prefixIcon: const Icon(Icons.subdirectory_arrow_right,
                size: 14, color: Color(0xFF555555)),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 26, minHeight: 24),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFF22C55E))),
          ),
          onSubmitted: (_) => _submit(),
          onTapOutside: (_) => _cancel(),
        ),
      ),
    );
  }
}
