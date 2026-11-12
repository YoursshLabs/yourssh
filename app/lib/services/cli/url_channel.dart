import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server.dart';

/// Delivers `yourssh://` URLs to [CliServer] as trusted `open` requests.
///
/// macOS hands URLs to the running app natively; the Swift side forwards them
/// over the `yourssh/url` channel (method `open`, argument: the URL string)
/// and queues any that arrive before Dart listens — [attach] sends `ready`
/// to flush that queue. On Windows/Linux the URL is argv of a new process:
/// a second launch is forwarded by single_instance, a cold launch calls
/// [openLaunchUrl]. The providers-ready wait and the same-URL debounce live
/// in [CliServer], shared with the socket/pipe path.
class UrlChannel {
  UrlChannel({
    required this.server,
    this.channel = kUrlMethodChannel,
  });

  final CliServer server;
  final MethodChannel channel;

  void attach() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        await open(call.arguments as String);
      }
    });
    // Flush URLs the native side queued. No native side (Windows/Linux)
    // throws MissingPluginException: nothing to flush.
    channel.invokeMethod<void>('ready').catchError((Object _) {});
  }

  /// Opens [url] (saved hosts only; the server rejects everything else).
  /// Never throws.
  Future<void> open(String url) async {
    try {
      final line = CliRequest(
              id: 'url', token: '', cmd: 'open', args: {'url': url})
          .encode();
      final resp = CliResponse.decode(
          await server.handleLine(line, trusted: true, source: 'url'));
      if (!resp.ok) debugPrint('[url] open refused: ${resp.code}');
    } catch (e) {
      debugPrint('[url] open failed: $e');
    }
  }

  /// Cold start: the launch argv carried a URL.
  Future<void> openLaunchUrl(List<String> args) async {
    for (final a in args) {
      if (a.toLowerCase().startsWith('yourssh://')) return open(a);
    }
  }
}

/// The `yourssh/url` method channel (MainFlutterWindow.swift on macOS).
const MethodChannel kUrlMethodChannel = MethodChannel('yourssh/url');

/// Brings the window forward for a CLI / URL request (the `focus` of
/// AppCliHandlers). window_manager's show()/focus() do not activate an app
/// that is in the background on macOS, so there the native side also runs
/// `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront`
/// (method `activate`). Windows relies on the client granting
/// AllowSetForegroundWindow before it sends the request; Linux is
/// unchanged. Never throws for a missing native handler.
Future<void> raiseWindowForCli({
  required bool isMacOS,
  required Future<void> Function() show,
  required Future<void> Function() focus,
  MethodChannel channel = kUrlMethodChannel,
}) async {
  await show();
  await focus();
  if (!isMacOS) return;
  try {
    await channel.invokeMethod<void>('activate');
  } on MissingPluginException {
    // No native handler (tests, older runner): window_manager's focus only.
  } on PlatformException catch (e) {
    debugPrint('[url] native activate failed: $e');
  }
}
