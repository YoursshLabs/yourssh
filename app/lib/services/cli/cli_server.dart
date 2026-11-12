import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/yourssh_cli.dart';

import '../../models/host.dart';
import 'cli_handlers.dart';
import 'host_resolver.dart';
import 'host_summary.dart';

/// Transport-independent request handling for the `yourssh` CLI and
/// `yourssh://` URLs. One request line in, one encoded response line out.
///
/// Every path goes through one instance — the socket/pipe listener (CLI and
/// forwarded launches) and the in-process URL channel (macOS events, a cold
/// launch's own URL) — so they share:
/// - the providers-ready gate: `ls`, `connect` and `open` wait for [ready]
///   (hosts, known hosts and keys loaded), at most [readyTimeout];
/// - the same-URL debounce: an `open` of a URL (any case) seen within
///   [dedupeWindow] is answered but opens nothing (drive-by flood).
class CliServer {
  CliServer({
    required this.handlers,
    required String token,
    Future<void>? ready,
    this.now = DateTime.now,
    this.readyTimeout = const Duration(seconds: 15),
    this.onUrlRefused,
  })  : _token = token,
        _ready = ready ?? Future<void>.value() {
    // A failing gate is reported per request; never as an unhandled error.
    _ready.catchError((Object _) {});
  }

  final CliHandlers handlers;
  final String _token;
  final Future<void> _ready;

  /// Clock for the URL debounce, injectable for tests.
  final DateTime Function() now;
  final Duration readyTimeout;

  /// Called when an `open` names no saved host or has an unsupported shape
  /// (the app shows it in the notification bell).
  final void Function(String url, String reason)? onUrlRefused;

  /// A repeat of the same URL inside this window is dropped.
  static const dedupeWindow = Duration(seconds: 2);
  final Map<String, DateTime> _recentUrls = {};

  /// The token the CLI must present; written to `cli.token` by the owner.
  String get token => _token;

  /// [trusted] skips the token check (in-process URL events). Never throws.
  Future<String> handleLine(
    String line, {
    required bool trusted,
    String source = 'cli',
  }) async {
    CliRequest req;
    try {
      req = CliRequest.decode(line);
    } on CliProtocolException catch (e) {
      return CliResponse.failure('', e.code, e.message).encode();
    } catch (_) {
      return CliResponse.failure('', CliExit.usage, 'invalid request').encode();
    }
    try {
      if (!trusted && !tokensEqual(req.token, _token)) {
        return CliResponse.failure(req.id, CliExit.denied, 'denied').encode();
      }
      if (trusted && req.cmd != 'open' && req.cmd != 'activate') {
        return CliResponse.failure(req.id, CliExit.denied, 'denied').encode();
      }
      validateArgs(req.cmd, req.args);
      if (req.cmd == 'open' && _isRepeatUrl(req.args['url'] as String)) {
        return CliResponse.success(req.id, {'ignored': 'repeat'}).encode();
      }
      if (const {'ls', 'connect', 'open'}.contains(req.cmd)) {
        await _waitReady();
      }
      final result = await _dispatch(req, source);
      return CliResponse.success(req.id, result).encode();
    } on _Failure catch (f) {
      if (req.cmd == 'open' && f.code == CliExit.usage) {
        _reportRefused(req.args['url'], f.message);
      }
      return CliResponse.failure(req.id, f.code, f.message,
              candidates: f.candidates)
          .encode();
    } on CliProtocolException catch (e) {
      return CliResponse.failure(req.id, e.code, e.message).encode();
    } catch (e) {
      // Detail stays local: it can contain hostnames, key paths, proxy info.
      debugPrint('CliServer: ${req.cmd} failed: $e');
      return CliResponse.failure(req.id, CliExit.runtime, 'internal error')
          .encode();
    }
  }

  bool _isRepeatUrl(String url) {
    final key = url.toLowerCase();
    final t = now();
    _recentUrls.removeWhere((_, at) => t.difference(at) >= dedupeWindow);
    if (_recentUrls.containsKey(key)) return true;
    _recentUrls[key] = t;
    return false;
  }

  Future<void> _waitReady() async {
    try {
      await _ready.timeout(readyTimeout);
    } on TimeoutException {
      throw _Failure(CliExit.unreachable, 'YourSSH is still starting; retry');
    }
    // Any other gate error falls through to the generic internal error.
  }

  void _reportRefused(Object? url, String reason) {
    if (url is! String) return;
    try {
      onUrlRefused?.call(url, reason);
    } catch (e) {
      debugPrint('CliServer: onUrlRefused failed: $e');
    }
  }

  Future<Object?> _dispatch(CliRequest req, String source) async {
    switch (req.cmd) {
      case 'version':
        return {'app': handlers.appVersion, 'protocol': kCliProtocolVersion};
      case 'activate':
        await handlers.focusWindow();
        return <String, Object?>{};
      case 'ls':
        return {'hosts': _ls(req.args)};
      case 'connect':
        return _connect(req.args['host'] as String, source: source, allowAdHoc: true);
      case 'open':
        final query = _hostFromUrl(req.args['url'] as String);
        return _connect(query, source: 'url', allowAdHoc: false);
    }
    throw _Failure(CliExit.usage, 'unknown command: ${req.cmd}');
  }

  List<Map<String, Object?>> _ls(Map<String, Object?> args) {
    final tag = (args['tag'] as String?)?.toLowerCase();
    final filter = (args['filter'] as String?)?.toLowerCase();
    return [
      for (final h in handlers.hosts)
        if ((tag == null || h.tags.any((t) => t.toLowerCase() == tag)) &&
            (filter == null ||
                h.label.toLowerCase().contains(filter) ||
                h.host.toLowerCase().contains(filter)))
          hostSummary(h),
    ];
  }

  Future<Object?> _connect(String query,
      {required String source, required bool allowAdHoc}) async {
    final r = resolveHost(query, handlers.hosts, allowAdHoc: allowAdHoc);
    switch (r) {
      case ResolvedHost(:final host):
        await handlers.connect(host, source: source);
        return {'host': hostSummary(host)};
      case AdHocTarget():
        await handlers.connectAdHoc(r);
        return {
          'host': {
            'id': null,
            'label': '${r.user}@${r.hostname}',
            'username': r.user,
            'host': r.hostname,
            'port': r.port,
          },
        };
      case AmbiguousHost(:final candidates):
        throw _Failure(CliExit.usage, 'ambiguous host: $query',
            candidates: [for (final Host h in candidates) hostSummary(h)]);
      case UnknownHost():
        throw _Failure(CliExit.usage, 'unknown host: $query');
    }
  }

  /// Accepts only `yourssh://connect/<one segment>`; returns the decoded
  /// segment. Everything else is a usage error.
  static String _hostFromUrl(String url) {
    final Uri u;
    try {
      u = Uri.parse(url);
    } on FormatException {
      throw _Failure(CliExit.usage, 'invalid URL');
    }
    if (u.scheme != 'yourssh' ||
        u.host != 'connect' ||
        u.hasQuery ||
        u.hasFragment ||
        u.userInfo.isNotEmpty ||
        u.hasPort) {
      throw _Failure(CliExit.usage, 'unsupported URL (only yourssh://connect/<host>)');
    }
    final raw = u.path.startsWith('/') ? u.path.substring(1) : u.path;
    if (raw.isEmpty || raw.contains('/')) {
      throw _Failure(CliExit.usage, 'URL must name exactly one saved host');
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } on FormatException {
      throw _Failure(CliExit.usage, 'invalid URL encoding');
    } on ArgumentError {
      throw _Failure(CliExit.usage, 'invalid URL encoding');
    }
    if (decoded.isEmpty || decoded.contains('/') || decoded.contains('\\')) {
      throw _Failure(CliExit.usage, 'URL must name exactly one saved host');
    }
    return decoded;
  }
}

class _Failure implements Exception {
  _Failure(this.code, this.message, {this.candidates});
  final CliExit code;
  final String message;
  final List<Map<String, Object?>>? candidates;
}
