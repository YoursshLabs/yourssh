import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../models/host.dart';

sealed class HostResolution {
  const HostResolution();
}

class ResolvedHost extends HostResolution {
  final Host host;
  const ResolvedHost(this.host);
}

class AmbiguousHost extends HostResolution {
  final List<Host> candidates;
  const AmbiguousHost(this.candidates);
}

class AdHocTarget extends HostResolution {
  final String user;
  final String hostname;
  final int port;
  const AdHocTarget(this.user, this.hostname, this.port);
}

class UnknownHost extends HostResolution {
  final String query;
  const UnknownHost(this.query);
}

String _norm(String s) => unorm.nfc(s.trim()).toLowerCase();

final _target = RegExp(r'^([^@\s]+)@([^@:\s]+)(?::(\d{1,5}))?$');

/// Order: exact id, label (case-insensitive, NFC, trimmed),
/// `user@hostname[:port]` matching a saved host, ad-hoc (if allowed), unknown.
HostResolution resolveHost(String query, List<Host> hosts,
    {required bool allowAdHoc}) {
  for (final h in hosts) {
    if (h.id == query) return ResolvedHost(h);
  }

  final q = _norm(query);
  if (q.isNotEmpty) {
    final byLabel = hosts.where((h) => _norm(h.label) == q).toList();
    if (byLabel.length == 1) return ResolvedHost(byLabel.first);
    if (byLabel.length > 1) return AmbiguousHost(byLabel);
  }

  final m = _target.firstMatch(query.trim());
  if (m != null) {
    final user = m.group(1)!;
    final hostname = m.group(2)!;
    final port = m.group(3) == null ? 22 : int.parse(m.group(3)!);
    if (port >= 1 && port <= 65535) {
      final matches = hosts
          .where((h) =>
              h.username == user &&
              h.host.toLowerCase() == hostname.toLowerCase() &&
              h.port == port)
          .toList();
      if (matches.length == 1) return ResolvedHost(matches.first);
      if (matches.length > 1) return AmbiguousHost(matches);
      if (allowAdHoc) return AdHocTarget(user, hostname, port);
    }
  }
  return UnknownHost(query);
}
