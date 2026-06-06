// Pure helper for the bulk Connect-all action. No Flutter imports.
import '../models/host.dart';

/// Splits [selected] into hosts to connect and the count skipped because
/// they already have a live (connecting/connected) session.
///
/// Callers pass a duplicate-free [selected] list (the dashboard derives it
/// from a Set of ids).
({List<Host> toConnect, int skipped}) planConnectAll({
  required List<Host> selected,
  required Set<String> liveHostIds,
}) {
  final toConnect = [
    for (final h in selected)
      if (!liveHostIds.contains(h.id)) h,
  ];
  return (toConnect: toConnect, skipped: selected.length - toConnect.length);
}
