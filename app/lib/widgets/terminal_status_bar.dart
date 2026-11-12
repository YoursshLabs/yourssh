import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/agent_forwarding_state.dart';
import '../models/app_session.dart';
import '../models/local_session.dart';
import '../models/rdp_session.dart';
import '../models/ssh_session.dart';
import '../models/vnc_session.dart';
import '../providers/host_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/session_provider.dart';
import '../services/local_shell_service.dart';
import 'session_tab.dart' show agentForwardingTooltip;

/// Bottom status line of a session workspace, on [YsStatusBar]. Shows only
/// what the app already tracks (spec "Mockups vs. real data"):
///
/// | Session   | Fields                                                     |
/// |-----------|------------------------------------------------------------|
/// | SSH       | status, user@host, agent forwarding, "via" jump chain,      |
/// |           | TERM, cols×rows, REC + elapsed                              |
/// | Local PTY | shell, cols×rows                                           |
/// | RDP / VNC | status, resolution                                         |
///
/// Every field carries a `ValueKey('status-<name>')`.
///
/// Rebuilds only on events, never on terminal output: SSH and local fields
/// `select` the session's status / agent-forwarding state on
/// [SessionProvider], the recording flag on [RecordingProvider], the jump
/// labels on [HostProvider]; TERM is the session's own connect-time snapshot
/// ([SshSession.termType]). RDP and VNC listen to `stateChanges` (not the
/// per-frame notifier). The two live
/// values have their own small widgets: [TerminalSizeText] (changes only when
/// the terminal is resized) and [RecElapsedText] (ticks once a second).
/// [debugBuildCount] counts bar builds so tests can assert that.
class SessionStatusBar extends StatelessWidget {
  @visibleForTesting
  static int debugBuildCount = 0;

  final AppSession session;
  const SessionStatusBar({super.key, required this.session});

  @override
  Widget build(BuildContext context) => switch (session) {
    SshSession s => _ssh(context, s),
    LocalSession s => _local(context, s),
    RdpSession s => ListenableBuilder(
      listenable: s.stateChanges,
      builder: (_, _) => _bar(
        leading: [_remoteStatus(_rdpStatus(s.status), s.lastMessage)],
        trailing: [
          // RDP starts at the requested size and only learns the real one
          // from the server's Connected event; no live desktop, no size.
          ?switch (s.status) {
            RdpSessionStatus.connected => _resolution(s.width, s.height),
            RdpSessionStatus.connecting => _resolution(
              s.width,
              s.height,
              requested: true,
            ),
            _ => null,
          },
        ],
      ),
    ),
    VncSession s => ListenableBuilder(
      listenable: s.stateChanges,
      builder: (_, _) => _bar(
        leading: [_remoteStatus(_vncStatus(s.status), s.lastMessage)],
        trailing: [
          // VNC knows no size before the server's first framebuffer.
          if (s.status == VncSessionStatus.connected)
            ?_resolution(s.width, s.height),
        ],
      ),
    ),
    _ => _bar(leading: const []),
  };

  Widget _bar({
    required List<Widget> leading,
    List<Widget> trailing = const [],
  }) {
    assert(() {
      debugBuildCount++;
      return true;
    }());
    return YsStatusBar(leading: leading, trailing: trailing);
  }

  Widget _ssh(BuildContext context, SshSession s) {
    final (
      status,
      agent,
      error,
      term,
    ) = _selectOr<
      SessionProvider,
      (SessionStatus, AgentForwardingState, String?, String?)
    >(
      context,
      (_) => (s.status, s.agentForwardingState, s.errorMessage, s.termType),
      fallback: (s.status, s.agentForwardingState, s.errorMessage, s.termType),
    );
    final recording =
        !s.isWatch &&
        _selectOr<RecordingProvider, bool>(
          context,
          (p) => p.isRecording(s.id),
          fallback: false,
        );
    final connected = status == SessionStatus.connected;
    final size = connected
        ? TerminalSizeText(
            key: const ValueKey('status-size'),
            terminal: s.terminal,
          )
        : null;

    if (s.isWatch) {
      return _bar(
        leading: [_sshStatus(status, error, watching: true)],
        trailing: [?size],
      );
    }

    final hops = s.host.jumpHostIds;
    final via = hops.isEmpty
        ? null
        : _selectOr<HostProvider, String>(
            context,
            (p) => hops
                .map((id) => p.byId(id)?.label ?? 'unknown host')
                .join(' → '),
            fallback: '${hops.length} hop${hops.length == 1 ? '' : 's'}',
          );
    final recorder = recording ? context.read<RecordingProvider>() : null;

    return _bar(
      leading: [
        _sshStatus(status, error),
        YsStatusItem(
          key: const ValueKey('status-user-host'),
          label: '${s.host.username}@${s.host.host}',
          color: YsColors.foreground,
        ),
        _agent(agent),
        if (via != null)
          YsStatusItem(
            key: const ValueKey('status-via'),
            label: 'via $via',
            tooltip: 'Jump chain: $via',
          ),
      ],
      trailing: [
        if (term != null)
          YsStatusItem(
            key: const ValueKey('status-term'),
            label: term,
            tooltip: 'TERM requested when the session connected',
          ),
        ?size,
        if (recorder != null)
          RecElapsedText(
            key: const ValueKey('status-rec'),
            elapsed: () => recorder.recordingElapsed(s.id) ?? Duration.zero,
          ),
      ],
    );
  }

  Widget _local(BuildContext context, LocalSession s) {
    final status = _selectOr<SessionProvider, LocalSessionStatus>(
      context,
      (_) => s.status,
      fallback: s.status,
    );
    final shell =
        s.profile?.name ?? LocalShellService.platformDefaultShellName();
    return _bar(
      leading: [
        YsStatusItem(
          key: const ValueKey('status-shell'),
          label: shell,
          icon: FLucideIcons.terminal,
          color: YsColors.foreground,
        ),
      ],
      trailing: [
        if (status == LocalSessionStatus.running)
          TerminalSizeText(
            key: const ValueKey('status-size'),
            terminal: s.terminal,
          ),
      ],
    );
  }

  /// `context.select` that degrades to [fallback] when the provider is
  /// absent — widget tests pump parts of the workspace without the full
  /// provider tree.
  static T _selectOr<P, T>(
    BuildContext context,
    T Function(P provider) selector, {
    required T fallback,
  }) {
    try {
      return context.select<P, T>(selector);
    } on ProviderNotFoundException {
      return fallback;
    }
  }
}

/// Status word, dot colour and optional detail of one session state.
typedef StatusLook = ({String label, Color color});

StatusLook _rdpStatus(RdpSessionStatus s) => switch (s) {
  RdpSessionStatus.connecting => (label: 'Connecting…', color: YsColors.warn),
  RdpSessionStatus.connected => (label: 'Connected', color: YsColors.ok),
  RdpSessionStatus.disconnected => (label: 'Disconnected', color: YsColors.off),
  RdpSessionStatus.error => (label: 'Error', color: YsColors.error),
};

StatusLook _vncStatus(VncSessionStatus s) => switch (s) {
  VncSessionStatus.connecting => (label: 'Connecting…', color: YsColors.warn),
  VncSessionStatus.connected => (label: 'Connected', color: YsColors.ok),
  VncSessionStatus.disconnected => (label: 'Disconnected', color: YsColors.off),
  VncSessionStatus.error => (label: 'Error', color: YsColors.error),
};

Widget _remoteStatus(StatusLook look, String? message) => YsStatusItem(
  key: const ValueKey('status-connection'),
  label: look.label,
  dotColor: look.color,
  color: YsColors.foreground,
  tooltip: look.label == 'Connected' ? null : message,
);

/// `W×H`, or `W×H (requested)` before the server negotiated the size.
Widget? _resolution(int width, int height, {bool requested = false}) =>
    width > 0 && height > 0
    ? YsStatusItem(
        key: const ValueKey('status-resolution'),
        label: requested ? '$width×$height (requested)' : '$width×$height',
        tooltip: requested
            ? 'Requested desktop size; the server may change it'
            : 'Desktop resolution',
      )
    : null;

Widget _sshStatus(
  SessionStatus status,
  String? error, {
  bool watching = false,
}) {
  final StatusLook look = switch (status) {
    SessionStatus.connecting => (label: 'Connecting…', color: YsColors.warn),
    SessionStatus.connected => (
      label: watching ? 'Watching' : 'Connected',
      color: YsColors.ok,
    ),
    SessionStatus.disconnected => (label: 'Disconnected', color: YsColors.off),
    SessionStatus.error => (label: 'Error', color: YsColors.error),
  };
  return YsStatusItem(
    key: const ValueKey('status-connection'),
    label: look.label,
    dotColor: look.color,
    color: YsColors.foreground,
    tooltip: status == SessionStatus.error ? error : null,
  );
}

Widget _agent(AgentForwardingState state) {
  final (label, color) = switch (state) {
    AgentForwardingState.off => ('Agent forwarding off', null),
    AgentForwardingState.ready => ('Agent forwarding ready', null),
    AgentForwardingState.active => ('Agent forwarding active', YsColors.ok),
    AgentForwardingState.fallback => (
      'Agent forwarding via Keychain',
      YsColors.warn,
    ),
    AgentForwardingState.refused => (
      'Agent forwarding refused',
      YsColors.error,
    ),
  };
  return YsStatusItem(
    key: const ValueKey('status-agent'),
    label: label,
    icon: FLucideIcons.keyRound,
    color: color,
    tooltip: agentForwardingTooltip(state),
  );
}

/// `HH:MM:SS` (hours are not capped) for the REC field.
String formatRecElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:'
      '${two(d.inSeconds.remainder(60))}';
}

/// The terminal's cols×rows. xterm resizes the terminal during the
/// TerminalView's layout and does not notify listeners, so this checks the
/// size once after each frame (two int compares) and rebuilds only when it
/// changed — terminal output alone never rebuilds it.
class TerminalSizeText extends StatefulWidget {
  @visibleForTesting
  static int debugBuildCount = 0;

  final Terminal terminal;
  const TerminalSizeText({super.key, required this.terminal});

  @override
  State<TerminalSizeText> createState() => _TerminalSizeTextState();
}

class _TerminalSizeTextState extends State<TerminalSizeText> {
  late int _cols = widget.terminal.viewWidth;
  late int _rows = widget.terminal.viewHeight;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback(_check);
  }

  void _check(Duration _) {
    if (!mounted) return;
    final t = widget.terminal;
    if (t.viewWidth != _cols || t.viewHeight != _rows) {
      setState(() {
        _cols = t.viewWidth;
        _rows = t.viewHeight;
      });
    }
    SchedulerBinding.instance.addPostFrameCallback(_check);
  }

  @override
  void didUpdateWidget(TerminalSizeText old) {
    super.didUpdateWidget(old);
    if (!identical(old.terminal, widget.terminal)) {
      _cols = widget.terminal.viewWidth;
      _rows = widget.terminal.viewHeight;
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      TerminalSizeText.debugBuildCount++;
      return true;
    }());
    return YsStatusItem(label: '$_cols×$_rows', tooltip: 'Columns × rows');
  }
}

/// Red `REC HH:MM:SS`, re-rendered on each whole second of [elapsed] (at
/// most once a second) by its own timer, so the bar itself never rebuilds
/// for the clock.
class RecElapsedText extends StatefulWidget {
  @visibleForTesting
  static int debugBuildCount = 0;

  final Duration Function() elapsed;
  const RecElapsedText({super.key, required this.elapsed});

  @override
  State<RecElapsedText> createState() => _RecElapsedTextState();
}

class _RecElapsedTextState extends State<RecElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  /// Fires at the next whole second of the recording's own clock.
  void _arm() {
    final ms = widget.elapsed().inMilliseconds;
    _timer = Timer(Duration(milliseconds: 1000 - ms % 1000), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      RecElapsedText.debugBuildCount++;
      return true;
    }());
    return YsStatusItem(
      label: 'REC ${formatRecElapsed(widget.elapsed())}',
      dotColor: YsColors.error,
      color: YsColors.error,
      tooltip: 'Recording this session',
    );
  }
}
