import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/local_session.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/shell_integration_provider.dart';

/// Workspace header identity for the active terminal: host label, `user@host`,
/// host tags and the shell-integration working directory. Only data that is
/// already tracked is shown (no tmux chip: tmux state is not tracked per
/// session).
///
/// Listens to nothing but the active session's cwd (a `select` on
/// [ShellIntegrationProvider]); it never watches the terminal buffer, so
/// output does not rebuild it. [debugBuildCount] lets a test assert that.
class TerminalHeaderChips extends StatelessWidget {
  @visibleForTesting
  static int debugBuildCount = 0;

  final TerminalSession session;
  const TerminalHeaderChips({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugBuildCount++;
      return true;
    }());
    final cwd = context.select<ShellIntegrationProvider, String?>(
        (p) => p.cwdFor(session.id));
    final s = session;
    final String title;
    String? subtitle;
    var tags = const <String>[];
    switch (s) {
      case SshSession():
        title = s.host.label.isNotEmpty ? s.host.label : s.tabLabel;
        subtitle = '${s.host.username}@${s.host.host}';
        tags = s.host.tags.take(2).toList();
      case LocalSession():
        title = s.tabLabel;
      default:
        title = s.tabLabel;
    }

    return ClipRect(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: YsSpace.s2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 12,
                    fontFamily: kYsMonoFontFamily,
                    fontFamilyFallback: kYsMonoFontFallback,
                  ),
                ),
              ),
            ],
            for (final t in tags) ...[
              const SizedBox(width: YsSpace.s2),
              YsTag(t),
            ],
            if (cwd != null && cwd.isNotEmpty) ...[
              const SizedBox(width: YsSpace.s2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  cwd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 12,
                    fontFamily: kYsMonoFontFamily,
                    fontFamilyFallback: kYsMonoFontFallback,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
