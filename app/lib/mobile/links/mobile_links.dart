import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_cli/yourssh_cli.dart' show generateToken, sanitize;
import 'package:yourssh_ui/yourssh_ui.dart' show showYsConfirm;

import '../../models/host.dart';
import '../../services/cli/cli_server.dart';
import '../../services/cli/link_refused.dart';
import '../../services/cli/url_channel.dart';
import '../../theme/app_theme.dart' show AppSnack;
import '../mobile_bootstrap.dart';
import '../navigation/open_session.dart';
import '../screens/mobile_add_host_screen.dart';
import '../security/app_lock_gate.dart' show mobileAppLocked;
import '../util/mobile_prefs.dart';
import 'mobile_cli_handlers.dart';
import 'ssh_link.dart';

/// The `yourssh/ssh_url` method channel (YourSshNative.swift on iOS): `ssh://`
/// URLs, kept apart from `yourssh/url` so they can be switched off.
const MethodChannel kSshUrlChannel = MethodChannel('yourssh/ssh_url');

/// Wires `yourssh://` (always) and `ssh://` (opt-in) links on iOS.
///
/// `yourssh://connect/<saved host>` goes through the same [CliServer] as the
/// desktop CLI and URL handling (one parser, one resolver): saved hosts only,
/// no ad-hoc targets, no commands. `ssh://user@host[:port]` opens a saved
/// match, or after a confirmation prefills the Add Host form; it never
/// connects to an unsaved target.
class MobileLinks {
  MobileLinks({
    required this.bootstrap,
    required this.navigator,
    required this.appVersion,
    this.urlChannel = kUrlMethodChannel,
    this.sshChannel = kSshUrlChannel,
    this.openSession = openMobileSession,
  });

  /// Opens a session; [openMobileSession] in production, replaced in tests.
  final Future<void> Function(NavigatorState nav, Host host,
      {String auditSource, bool resetStack}) openSession;

  final MobileBootstrap bootstrap;
  final GlobalKey<NavigatorState> navigator;
  final String appVersion;
  final MethodChannel urlChannel;
  final MethodChannel sshChannel;

  late final Future<void> _ready = Future.wait<void>([
    bootstrap.hostProvider.ready,
    bootstrap.knownHosts.ready,
    bootstrap.keyProvider.ready,
  ]);

  /// Newest link wins while the app is locked: a flood of links cannot open a
  /// pile of sessions once the user unlocks.
  int _generation = 0;

  void attach() {
    final server = CliServer(
      handlers: MobileCliHandlers(
        hostProvider: bootstrap.hostProvider,
        appVersion: appVersion,
        open: (host, source) => _whenUnlocked(
            () => _openHost(host, source)),
      ),
      // Never written anywhere: only the in-process URL channel (trusted
      // `open`) can reach this server.
      token: generateToken(),
      ready: _ready,
      onUrlRefused: (url, reason) {
        final n = linkRefusedNotification(url, reason);
        _toast(n.title);
      },
    );
    UrlChannel(server: server, channel: urlChannel).attach();

    final ssh = SshLinkHandler(
      hosts: () => bootstrap.hostProvider.allHosts,
      enabled: () async =>
          (await SharedPreferences.getInstance()).getBool(kSshLinksPrefKey) ??
          false,
      openSaved: (host) =>
          _whenUnlocked(() => _openHost(host, 'url')),
      confirm: _confirm,
      addHost: (prefill) => unawaited(_whenUnlocked(() async {
        final nav = navigator.currentState;
        if (nav == null) return;
        nav.popUntil((r) => r.isFirst);
        await nav.push(MaterialPageRoute<void>(
            builder: (_) => MobileAddHostScreen(prefill: prefill)));
      })),
      refused: _toast,
    );
    sshChannel.setMethodCallHandler((call) async {
      if (call.method != 'open' || call.arguments is! String) return;
      try {
        await _ready.timeout(CliServer.defaultReadyTimeout);
        await ssh.handle(call.arguments as String);
      } catch (e) {
        debugPrint('[ssh-url] failed: $e');
      }
    });
    // Flush URLs the native side queued before Dart listened.
    sshChannel.invokeMethod<void>('ready').catchError((Object _) {});
  }

  Future<void> _openHost(Host host, String source) async {
    final nav = navigator.currentState;
    if (nav == null) return;
    await openSession(nav, host, auditSource: source, resetStack: true);
  }

  Future<bool> _confirm(SshLinkTarget t) async {
    final ctx = navigator.currentContext;
    if (ctx == null) return false;
    // Nothing is shown while locked; wait, but let a newer link supersede.
    var ok = false;
    await _whenUnlocked(() async {
      final c = navigator.currentContext;
      if (c == null) return;
      ok = await showYsConfirm(
        c,
        title: 'Open ssh:// link?',
        message:
            'A link wants to add ${sanitize(t.query)} as a new host. Nothing '
            'is saved or connected until you review and save it.',
        confirmLabel: 'Review',
      );
    });
    return ok;
  }

  /// Runs [action] now, or once the app is unlocked; dropped if a newer link
  /// arrived meanwhile.
  Future<void> _whenUnlocked(Future<void> Function() action) async {
    final mine = ++_generation;
    if (mobileAppLocked.value) {
      final done = Completer<void>();
      void listener() {
        if (!mobileAppLocked.value && !done.isCompleted) done.complete();
      }

      mobileAppLocked.addListener(listener);
      try {
        await done.future;
      } finally {
        mobileAppLocked.removeListener(listener);
      }
      if (mine != _generation) return;
    }
    await action();
  }

  void _toast(String message) {
    final ctx = navigator.currentContext;
    if (ctx != null) AppSnack.error(ctx, message);
  }
}
