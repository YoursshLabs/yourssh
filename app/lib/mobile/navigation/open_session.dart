import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../platform/runtime_platform.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../screens/mobile_port_forward_screen.dart';
import '../screens/mobile_sftp_screen.dart';
import '../screens/mobile_terminal_screen.dart';

/// Whether [host] can be opened on this platform: SSH everywhere, RDP/VNC only
/// where [supportsRemoteDesktop] is true.
bool canOpenOnMobile(Host host) =>
    host.protocol == HostProtocol.ssh || supportsRemoteDesktop;

/// Opens [host] in the mobile terminal: reuses its live SSH session or starts a
/// new one, then pushes [MobileTerminalScreen]. [resetStack] pops to the first
/// route before pushing (used by links). [SessionProvider] is read from
/// `nav.context` (the providers sit above `MaterialApp`).
Future<void> openMobileSession(
  NavigatorState nav,
  Host host, {
  String auditSource = 'app',
  bool resetStack = false,
}) async {
  if (!canOpenOnMobile(host)) {
    AppSnack.info(nav.context, 'RDP and VNC hosts open in the desktop app');
    return;
  }
  final sp = nav.context.read<SessionProvider>();

  final existing = sp.sshSessions.where((s) => s.host.id == host.id).toList();
  String? sessionId;
  if (existing.isNotEmpty) {
    sessionId = existing.last.id;
  } else {
    // The connect future must NOT be awaited: SessionProvider._doConnect awaits
    // SshService.openShell, which only completes once the shell closes, so
    // awaiting it would strand the user on the host list for the whole session.
    // The session is registered synchronously, so the terminal can pick it up
    // now and render its own connecting state.
    unawaited(sp.connectAny(host, auditSource: auditSource));
    final after = sp.sshSessions.where((s) => s.host.id == host.id).toList();
    sessionId = after.isNotEmpty ? after.last.id : null;
  }
  if (!nav.mounted) return;
  if (resetStack) nav.popUntil((r) => r.isFirst);
  await nav.push(
    MaterialPageRoute(
      builder: (ctx) => MobileTerminalScreen(
        focusSessionId: sessionId,
        onOpenFiles: (h) => Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => MobileSftpScreen(host: h)),
        ),
        onOpenPortForward: (h) => Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => MobilePortForwardScreen(host: h)),
        ),
      ),
    ),
  );
}
