import '../../models/host.dart';
import '../../services/cli/cli_server.dart';
import '../../services/cli/host_resolver.dart';

/// Longest `ssh://` link considered at all.
const int kMaxSshLinkLength = 2048;

/// `user@host[:port]` from an `ssh://` link.
class SshLinkTarget {
  const SshLinkTarget(this.user, this.host, this.port);

  final String user;

  /// Hostname, IPv4 or IPv6 (without brackets).
  final String host;
  final int port;

  /// The query [resolveHost] understands (`user@host:port`, IPv6 bracketed).
  String get query => '$user@${host.contains(':') ? '[$host]' : host}:$port';

  /// Display form, identical to [query].
  @override
  String toString() => query;
}

// user: [A-Za-z0-9._-]+; host: DNS name / IPv4 or [IPv6]; optional port and a
// single trailing slash. Nothing else: no password, `;` parameters, path,
// query or fragment. `$` (no multiLine) only matches at the very end, so a
// trailing newline does not slip through.
final _sshLink = RegExp(
    r'^ssh://([A-Za-z0-9._-]+)@(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::(\d{1,5}))?/?$',
    caseSensitive: false);

/// Parses `ssh://user@host[:port]` (optional trailing `/`); null for anything
/// else. Never throws.
SshLinkTarget? parseSshLink(String url) {
  if (url.length > kMaxSshLinkLength) return null;
  final m = _sshLink.firstMatch(url);
  if (m == null) return null;
  final user = m.group(1)!;
  var host = m.group(2)!;
  if (host.startsWith('[')) host = host.substring(1, host.length - 1);
  final port = m.group(3) == null ? 22 : int.parse(m.group(3)!);
  if (port < 1 || port > 65535) return null;
  // A leading '-' could be parsed as an ssh option downstream.
  if (user.startsWith('-') || host.startsWith('-') || host.isEmpty) return null;
  return SshLinkTarget(user, host, port);
}

/// Decides what an `ssh://` link may do: open a saved host, or after an
/// explicit confirmation prefill (never save, never connect) a new host.
class SshLinkHandler {
  SshLinkHandler({
    required this.hosts,
    required this.enabled,
    required this.openSaved,
    required this.confirm,
    required this.addHost,
    required this.refused,
    this.now = DateTime.now,
  });

  final List<Host> Function() hosts;
  final Future<bool> Function() enabled;
  final Future<void> Function(Host host) openSaved;
  final Future<bool> Function(SshLinkTarget t) confirm;
  final void Function(Host prefill) addHost;

  /// Shows a refusal. Messages are fixed strings: the link text is never
  /// echoed (it comes from another app or a web page).
  final void Function(String message) refused;
  final DateTime Function() now;

  final Map<String, DateTime> _recent = {};
  bool _confirming = false;

  Future<void> handle(String url) async {
    if (url.length > kMaxSshLinkLength) {
      refused('ssh:// link refused: too long');
      return;
    }
    if (_isRepeat(url)) return;
    if (!await enabled()) {
      refused('ssh:// links are off (Settings › Security)');
      return;
    }
    final t = parseSshLink(url);
    if (t == null) {
      refused('ssh:// link refused: only ssh://user@host[:port] is supported');
      return;
    }
    switch (resolveHost(t.query, hosts(), allowAdHoc: true)) {
      case ResolvedHost(:final host):
        // The resolver also matches by label: a host merely LABELLED
        // "user@host:port" must not stand in for a different target.
        if (host.username != t.user ||
            host.host.toLowerCase() != t.host.toLowerCase() ||
            host.port != t.port) {
          refused('ssh:// link refused: no saved host for that target');
          return;
        }
        await openSaved(host);
      case AmbiguousHost():
        refused('ssh:// link refused: several saved hosts match');
      case UnknownHost():
        refused('ssh:// link refused');
      case AdHocTarget():
        if (_confirming) {
          refused('ssh:// link refused: another link is waiting for an answer');
          return;
        }
        _confirming = true;
        try {
          if (!await confirm(t)) return;
        } finally {
          _confirming = false;
        }
        addHost(Host(
          label: '${t.user}@${t.host}',
          host: t.host,
          port: t.port,
          username: t.user,
        ));
    }
  }

  bool _isRepeat(String url) {
    final key = url.toLowerCase();
    final t = now();
    _recent.removeWhere((_, at) => t.difference(at) >= CliServer.dedupeWindow);
    if (_recent.containsKey(key)) return true;
    _recent[key] = t;
    return false;
  }
}
