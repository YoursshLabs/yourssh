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
/// [openLaunchUrl].
class UrlChannel {
  UrlChannel({
    required this.server,
    this.channel = const MethodChannel('yourssh/url'),
    Future<void>? ready,
    this.now = DateTime.now,
  }) : _ready = ready ?? Future<void>.value();

  final CliServer server;
  final MethodChannel channel;
  
  /// Clock, injectable for tests.
  final DateTime Function() now;

  /// A repeat of the same URL inside this window is dropped (drive-by flood).
  static const dedupeWindow = Duration(seconds: 2);
  final Map<String, DateTime> _recent = {};

  /// Completes when saved hosts are loaded; opens wait for it.
  final Future<void> _ready;

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
    final key = url.toLowerCase();
    final t = now();
    _recent.removeWhere((_, at) => t.difference(at) >= dedupeWindow);
    if (_recent.containsKey(key)) return;
    _recent[key] = t;
    try {
      await _ready;
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
