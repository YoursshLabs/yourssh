part of 'hosts_dashboard.dart';

// ── Facet chips + "x of N hosts" ──────────────────────────

/// Facet chips on the left (when any host has a `key:value` tag) and the
/// "x of N hosts" count on the right, as in the B-1 mockup.
class _FilterRow extends StatelessWidget {
  final List<String> facets;
  final String query;
  final void Function(String facet) onToggle;
  final int filteredCount;
  final int totalHosts;

  const _FilterRow({
    required this.facets,
    required this.query,
    required this.onToggle,
    required this.filteredCount,
    required this.totalHosts,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: facets.isEmpty
              ? const SizedBox(height: 32)
              : _FacetChipBar(facets: facets, query: query, onToggle: onToggle),
        ),
        const SizedBox(width: YsSpace.s3),
        const Icon(FLucideIcons.listFilter,
            size: 14, color: YsColors.mutedForeground),
        const SizedBox(width: YsSpace.s1),
        Text(
          '$filteredCount of $totalHosts hosts',
          style: const TextStyle(color: YsColors.mutedForeground, fontSize: 12),
        ),
      ],
    );
  }
}

/// Selectable badges, one per facet; a tap toggles the facet token in the
/// search query. Active facets use the primary (amber) badge.
class _FacetChipBar extends StatelessWidget {
  final List<String> facets;
  final String query;
  final void Function(String facet) onToggle;

  const _FacetChipBar({
    required this.facets,
    required this.query,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = HostQuery.parse(query);
    bool isActive(String facet) {
      final colon = facet.indexOf(':');
      if (colon <= 0) return false;
      final key = facet.substring(0, colon);
      final value = facet.substring(colon + 1);
      return parsed.facets[key]?.contains(value) ?? false;
    }
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: facets.length,
        separatorBuilder: (context, index) => const SizedBox(width: YsSpace.s2),
        itemBuilder: (_, i) {
          final facet = facets[i];
          final on = isActive(facet);
          return Center(
            child: FTappable(
              key: ValueKey('facet-$facet'),
              selected: on,
              onPress: () => onToggle(facet),
              child: FBadge(
                variant: on ? .primary : .outline,
                child: Text(facet),
              ),
            ),
          );
        },
      ),
    );
  }
}
