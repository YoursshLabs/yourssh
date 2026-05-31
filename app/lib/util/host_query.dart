import '../models/host.dart';

/// Parsed representation of a hosts filter query.
///
/// Tokens containing a non-empty `key:value` pair (split on the first `:`)
/// become *facets*; everything else (including malformed tokens like `env:` or
/// `:prod`) becomes a free-text *term*. All text is lower-cased.
class HostQuery {
  final Map<String, Set<String>> facets;
  final List<String> terms;

  const HostQuery._(this.facets, this.terms);

  bool get isEmpty => facets.isEmpty && terms.isEmpty;

  factory HostQuery.parse(String raw) {
    final facets = <String, Set<String>>{};
    final terms = <String>[];
    for (final token in raw.toLowerCase().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final colon = token.indexOf(':');
      if (colon > 0 && colon < token.length - 1) {
        final key = token.substring(0, colon);
        final value = token.substring(colon + 1);
        (facets[key] ??= <String>{}).add(value);
      } else {
        terms.add(token);
      }
    }
    final frozenFacets = {
      for (final e in facets.entries) e.key: Set<String>.unmodifiable(e.value),
    };
    return HostQuery._(Map.unmodifiable(frozenFacets), List.unmodifiable(terms));
  }

  bool matches(Host host) {
    if (isEmpty) return true;

    final tags = host.tags.map((t) => t.toLowerCase()).toList();

    // Facets: OR within a key, AND across keys.
    for (final entry in facets.entries) {
      final ok = entry.value.any((value) => tags.contains('${entry.key}:$value'));
      if (!ok) return false;
    }

    if (terms.isNotEmpty) {
      final label = host.label.toLowerCase();
      final addr = host.host.toLowerCase();
      final user = host.username.toLowerCase();
      // Tag value = part after first ':', or the whole tag if it has none.
      final tagValues = tags.map((t) {
        final i = t.indexOf(':');
        return i >= 0 ? t.substring(i + 1) : t;
      }).toList();
      for (final term in terms) {
        final hit = label.contains(term) ||
            addr.contains(term) ||
            user.contains(term) ||
            tagValues.any((v) => v.contains(term));
        if (!hit) return false;
      }
    }
    return true;
  }

  /// Distinct `key:value` tags across [hosts], deduped (case-insensitive) and
  /// sorted — used to render suggestion chips.
  static List<String> availableFacets(List<Host> hosts) {
    final seen = <String>{};
    for (final host in hosts) {
      for (final tag in host.tags) {
        if (tag.contains(':')) seen.add(tag.toLowerCase());
      }
    }
    return seen.toList()..sort();
  }

  /// Toggles [token] in [query]: removes it if present (case-insensitive),
  /// otherwise appends it. Returns the new whitespace-joined query string.
  static String toggleToken(String query, String token) {
    final tokens =
        query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final lower = token.toLowerCase();
    final idx = tokens.indexWhere((t) => t.toLowerCase() == lower);
    if (idx >= 0) {
      tokens.removeAt(idx);
    } else {
      tokens.add(token);
    }
    return tokens.join(' ');
  }
}
