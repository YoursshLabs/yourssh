import 'package:flutter/material.dart';

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
class PathBreadcrumb extends StatelessWidget {
  final List<PathCrumb> crumbs;
  final ValueChanged<String> onNavigate;

  const PathBreadcrumb({super.key, required this.crumbs, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.chevron_right, size: 13, color: Color(0xFF444444)),
              ),
            GestureDetector(
              onTap: () => onNavigate(crumbs[i].path),
              child: Text(
                crumbs[i].label,
                style: TextStyle(
                  color: i == crumbs.length - 1
                      ? const Color(0xFFD4D4D4)
                      : const Color(0xFF666666),
                  fontSize: 12,
                  fontWeight:
                      i == crumbs.length - 1 ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
