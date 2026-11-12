import '../../models/host.dart';

/// Secret-free host description for `ls` / `--json`. Whitelist only: never
/// add credentials, key ids, env vars or snippets here.
Map<String, Object?> hostSummary(Host h) => {
      'id': h.id,
      'label': h.label,
      'username': h.username,
      'host': h.host,
      'port': h.port,
      'protocol': h.protocol.name,
      'tags': List<String>.of(h.tags),
      'jumpHostIds': List<String>.of(h.jumpHostIds),
    };
