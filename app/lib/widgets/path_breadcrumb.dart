import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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

/// Clickable path segments on an [FBreadcrumb]; the last crumb is the
/// current directory. Scrolls horizontally when the path is longer than the
/// row and starts scrolled to the end, so the current folder stays visible.
/// Owns no navigation logic — panels supply [crumbs] and handle
/// [onNavigate].
///
/// When [editablePath] is non-null, a trailing edit affordance lets the user
/// type an arbitrary path to jump to; the value seeds the inline editor and
/// submitting it routes through [onNavigate] just like a crumb tap. Escape
/// or a tap outside cancels.
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
    final last = widget.crumbs.length - 1;
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              // At least as wide as the row so a short path stays at the
              // start instead of the reversed end.
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _crumbs(last),
                ),
              ),
            ),
          ),
        ),
        if (widget.editablePath != null)
          Tooltip(
            message: 'Go to path',
            excludeFromSemantics: true,
            child: FButton.icon(
              variant: .ghost,
              size: .xs,
              semanticsLabel: 'Go to path',
              onPress: _startEditing,
              child: const Icon(FLucideIcons.pencil),
            ),
          ),
      ],
    );
  }

  Widget _crumbs(int last) => FBreadcrumb(
        children: [
          for (int i = 0; i <= last; i++)
            FBreadcrumbItem(
              current: i == last,
              onPress: () => widget.onNavigate(widget.crumbs[i].path),
              child: Text(
                widget.crumbs[i].label,
                style: i == last
                    ? const TextStyle(fontWeight: FontWeight.w500)
                    : null,
              ),
            ),
        ],
      );

  Widget _buildEditor() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: FTextField(
        key: const Key('path-breadcrumb-editor'),
        control: FTextFieldControl.managed(controller: _controller),
        autofocus: true,
        size: .sm,
        hint: 'Enter a path and press Enter…',
        style: .delta(
          contentTextStyle: .delta([
            .base(
              const .delta(
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
              ),
            ),
          ]),
        ),
        prefixBuilder: (context, style, variants) =>
            FTextField.prefixIconBuilder(context, style, variants,
                const Icon(FLucideIcons.cornerDownRight)),
        onSubmit: (_) => _submit(),
        onTapOutside: (_) => _cancel(),
      ),
    );
  }
}
