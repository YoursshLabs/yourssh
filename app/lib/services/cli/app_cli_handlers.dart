import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import 'cli_handlers.dart';
import 'host_resolver.dart';

/// Bridges CLI / URL requests to the real app providers.
class AppCliHandlers implements CliHandlers {
  AppCliHandlers({
    required this.sessions,
    required this.hostProvider,
    required this.focus,
    required this.appVersion,
  });

  final SessionProvider sessions;
  final HostProvider hostProvider;
  final Future<void> Function() focus;

  @override
  final String appVersion;

  /// Upper bound on waiting for the tab to appear (RDP/VNC do some async
  /// setup first). Authentication is never awaited.
  static const Duration _tabWait = Duration(seconds: 10);

  @override
  List<Host> get hosts => hostProvider.allHosts;

  @override
  Future<void> connect(Host host, {required String source}) async {
    await _open(host, source);
    await focus();
  }

  @override
  Future<void> connectAdHoc(AdHocTarget target) async {
    final host = Host(
      label: '${target.user}@${target.hostname}',
      host: target.hostname,
      port: target.port,
      username: target.user,
    );
    await _open(host, 'cli');
    await focus();
  }

  /// Starts the connection and returns as soon as its tab exists. The
  /// connect future can last minutes (TOFU / password prompts, or the whole
  /// shell lifetime), so it is not awaited; its failures show in the tab.
  Future<void> _open(Host host, String source) async {
    final before = sessions.sessions.length;
    final done = Completer<void>();
    void onChange() {
      if (!done.isCompleted && sessions.sessions.length > before) {
        done.complete();
      }
    }

    sessions.addListener(onChange);
    try {
      final f = sessions.connectAny(host, auditSource: source);
      unawaited(f.then<void>((_) {
        if (!done.isCompleted) done.complete();
      }, onError: (Object e) {
        debugPrint('AppCliHandlers: connect failed: $e');
        if (!done.isCompleted) done.complete();
      }));
      onChange(); // SSH tabs are added synchronously by connect()
      await done.future.timeout(_tabWait, onTimeout: () {});
    } finally {
      sessions.removeListener(onChange);
    }
  }

  @override
  Future<void> focusWindow() => focus();
}
