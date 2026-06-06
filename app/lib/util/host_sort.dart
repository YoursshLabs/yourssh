import '../models/host.dart';

/// Dashboard host orderings. [key] is the value persisted in
/// SharedPreferences (`dashboardSort`); [label] is the dropdown text.
enum HostSortMode {
  nameAsc('name_asc', 'Name A→Z'),
  nameDesc('name_desc', 'Name Z→A'),
  createdDesc('created_desc', 'Newest first'),
  createdAsc('created_asc', 'Oldest first'),
  hostAsc('host_asc', 'Host A→Z'),
  hostDesc('host_desc', 'Host Z→A');

  const HostSortMode(this.key, this.label);
  final String key;
  final String label;

  /// Unknown or null persisted values fall back to the default.
  static HostSortMode fromKey(String? key) => values
      .firstWhere((m) => m.key == key, orElse: () => HostSortMode.nameAsc);
}

/// Returns a new list sorted by [mode]. Comparisons on label/host are
/// case-insensitive; ties break by label then id so the order is stable
/// across rebuilds regardless of input order.
List<Host> sortHosts(List<Host> hosts, HostSortMode mode) {
  int byLabel(Host a, Host b) {
    final c = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  int cmp(Host a, Host b) {
    switch (mode) {
      case HostSortMode.nameAsc:
        return byLabel(a, b);
      case HostSortMode.nameDesc:
        return byLabel(b, a);
      case HostSortMode.createdDesc:
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : byLabel(a, b);
      case HostSortMode.createdAsc:
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : byLabel(a, b);
      case HostSortMode.hostAsc:
        final c = a.host.toLowerCase().compareTo(b.host.toLowerCase());
        return c != 0 ? c : byLabel(a, b);
      case HostSortMode.hostDesc:
        final c = b.host.toLowerCase().compareTo(a.host.toLowerCase());
        return c != 0 ? c : byLabel(a, b);
    }
  }

  return List<Host>.of(hosts)..sort(cmp);
}
