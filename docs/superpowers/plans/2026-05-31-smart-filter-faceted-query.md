# Smart Filter + Faceted Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the hosts dashboard filter 50+ hosts with a faceted query (`env:prod role:db` + free-text) plus toggleable suggestion chips.

**Architecture:** A pure-Dart `HostQuery` (parse + match + helpers) holds all filtering logic and is unit-tested in isolation. The dashboard widget switches from its ad-hoc `label/host/username` substring filter to `HostQuery`, sourcing from `HostProvider.allHosts`, and renders a horizontal chip bar that toggles facet tokens into the search string.

**Tech Stack:** Dart, Flutter, `provider`, `flutter_test`. Run commands from the `app/` directory.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `app/lib/util/host_query.dart` | **new** — parse query string, match a `Host`, list available facets, toggle a token. No Flutter imports. |
| `app/test/util/host_query_test.dart` | **new** — unit tests for `HostQuery`. |
| `app/lib/widgets/hosts_dashboard.dart` | wire `HostQuery` into filtering; add `_FacetChipBar`. |
| `app/lib/widgets/host_detail_panel.dart` | update tags field hint only. |

`Host` (`app/lib/models/host.dart`) is unchanged: fields used are `label`, `host`, `username` (all `String`) and `tags` (`List<String>`).

---

## Task 1: HostQuery parsing

**Files:**
- Create: `app/lib/util/host_query.dart`
- Test: `app/test/util/host_query_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/util/host_query_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/host_query.dart';

void main() {
  group('HostQuery.parse', () {
    test('empty / whitespace query is empty', () {
      expect(HostQuery.parse('').isEmpty, isTrue);
      expect(HostQuery.parse('   ').isEmpty, isTrue);
    });

    test('key:value token becomes a facet', () {
      final q = HostQuery.parse('env:prod');
      expect(q.facets, {'env': {'prod'}});
      expect(q.terms, isEmpty);
    });

    test('same key collects multiple values', () {
      final q = HostQuery.parse('env:prod env:staging');
      expect(q.facets, {'env': {'prod', 'staging'}});
    });

    test('plain token becomes a free-text term', () {
      final q = HostQuery.parse('web');
      expect(q.terms, ['web']);
      expect(q.facets, isEmpty);
    });

    test('malformed tokens demote to free-text', () {
      final q = HostQuery.parse('env: :prod');
      expect(q.facets, isEmpty);
      expect(q.terms, ['env:', ':prod']);
    });

    test('a:b:c splits on first colon', () {
      final q = HostQuery.parse('a:b:c');
      expect(q.facets, {'a': {'b:c'}});
    });

    test('parsing is case-insensitive (lower-cased)', () {
      final q = HostQuery.parse('Env:Prod WEB');
      expect(q.facets, {'env': {'prod'}});
      expect(q.terms, ['web']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/util/host_query_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh/util/host_query.dart'` (file does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/util/host_query.dart`:

```dart
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
    return HostQuery._(facets, terms);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/util/host_query_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/host_query.dart app/test/util/host_query_test.dart
git commit -m "feat(filter): add HostQuery parser for faceted host search"
```

---

## Task 2: HostQuery.matches

**Files:**
- Modify: `app/lib/util/host_query.dart`
- Test: `app/test/util/host_query_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `app/test/util/host_query_test.dart`:

```dart
  group('HostQuery.matches', () {
    Host h({String label = 'srv', String host = '10.0.0.1', String username = 'root', List<String> tags = const []}) =>
        Host(label: label, host: host, username: username, tags: tags);

    test('empty query matches everything', () {
      expect(HostQuery.parse('').matches(h()), isTrue);
    });

    test('single facet exact match', () {
      expect(HostQuery.parse('env:prod').matches(h(tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('env:prod').matches(h(tags: ['env:staging'])), isFalse);
    });

    test('same key ORs values', () {
      final q = HostQuery.parse('env:prod env:staging');
      expect(q.matches(h(tags: ['env:staging'])), isTrue);
      expect(q.matches(h(tags: ['env:dev'])), isFalse);
    });

    test('different keys AND together', () {
      final q = HostQuery.parse('env:prod role:db');
      expect(q.matches(h(tags: ['env:prod', 'role:db'])), isTrue);
      expect(q.matches(h(tags: ['env:prod'])), isFalse);
    });

    test('free-text matches label/host/username/tag-value', () {
      expect(HostQuery.parse('web').matches(h(label: 'web-1')), isTrue);
      expect(HostQuery.parse('10.0').matches(h(host: '10.0.0.5')), isTrue);
      expect(HostQuery.parse('root').matches(h(username: 'root')), isTrue);
      expect(HostQuery.parse('prod').matches(h(tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('absent').matches(h()), isFalse);
    });

    test('free-text terms AND together', () {
      expect(HostQuery.parse('web prod').matches(h(label: 'web-1', tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('web prod').matches(h(label: 'web-1')), isFalse);
    });

    test('matching is case-insensitive', () {
      expect(HostQuery.parse('ENV:PROD').matches(h(tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('WEB').matches(h(label: 'Web-1')), isTrue);
    });
  });
```

Add the import at the top of the test file (below the existing import):

```dart
import 'package:yourssh/models/host.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/util/host_query_test.dart`
Expected: FAIL — `The method 'matches' isn't defined for the type 'HostQuery'`.

- [ ] **Step 3: Write minimal implementation**

Add this method to the `HostQuery` class in `app/lib/util/host_query.dart` (after the `parse` factory):

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/util/host_query_test.dart`
Expected: PASS (all parse + matches tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/host_query.dart app/test/util/host_query_test.dart
git commit -m "feat(filter): add HostQuery.matches with faceted OR/AND semantics"
```

---

## Task 3: availableFacets + toggleToken helpers

**Files:**
- Modify: `app/lib/util/host_query.dart`
- Test: `app/test/util/host_query_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `app/test/util/host_query_test.dart`:

```dart
  group('HostQuery.availableFacets', () {
    Host h(List<String> tags) => Host(label: 'l', host: 'h', username: 'u', tags: tags);

    test('returns distinct key:value tags, sorted, lower-cased', () {
      final facets = HostQuery.availableFacets([
        h(['env:prod', 'role:db']),
        h(['Env:Prod', 'plainlabel']),
        h(['region:sg']),
      ]);
      expect(facets, ['env:prod', 'region:sg', 'role:db']);
    });

    test('ignores tags without a colon', () {
      expect(HostQuery.availableFacets([h(['legacy', 'env:dev'])]), ['env:dev']);
    });
  });

  group('HostQuery.toggleToken', () {
    test('appends when absent', () {
      expect(HostQuery.toggleToken('', 'env:prod'), 'env:prod');
      expect(HostQuery.toggleToken('role:db', 'env:prod'), 'role:db env:prod');
    });

    test('removes when present (case-insensitive)', () {
      expect(HostQuery.toggleToken('env:prod role:db', 'env:prod'), 'role:db');
      expect(HostQuery.toggleToken('ENV:PROD', 'env:prod'), '');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/util/host_query_test.dart`
Expected: FAIL — `The method 'availableFacets' isn't defined for the type 'HostQuery'`.

- [ ] **Step 3: Write minimal implementation**

Add these two static methods to the `HostQuery` class in `app/lib/util/host_query.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/util/host_query_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/host_query.dart app/test/util/host_query_test.dart
git commit -m "feat(filter): add availableFacets + toggleToken helpers to HostQuery"
```

---

## Task 4: Wire HostQuery into the dashboard filter

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (imports + `_HostsDashboardState.build` lines ~34-42)

- [ ] **Step 1: Add the import**

At the top of `app/lib/widgets/hosts_dashboard.dart`, add alongside the other imports:

```dart
import '../util/host_query.dart';
```

- [ ] **Step 2: Replace the filter block**

In `_HostsDashboardState.build`, replace these lines:

```dart
    final hostProvider = context.watch<HostProvider>();
    final hosts = hostProvider.hosts;
    final query = _search.toLowerCase();
    final filtered = _search.isEmpty
        ? hosts
        : hosts.where((h) =>
            h.label.toLowerCase().contains(query) ||
            h.host.toLowerCase().contains(query) ||
            h.username.toLowerCase().contains(query)).toList();
```

with:

```dart
    final hostProvider = context.watch<HostProvider>();
    final hosts = hostProvider.allHosts;
    final query = HostQuery.parse(_search);
    final filtered =
        query.isEmpty ? hosts : hosts.where(query.matches).toList();
```

(Everything below — `pinnedGroupsUpper`, the `groups` map, `_TopBar`, the `filtered`/`hosts.length` counts — keeps working because `hosts` is now `allHosts`, which equals the previously-unfiltered list.)

- [ ] **Step 3: Verify analyzer + existing tests**

Run: `cd app && flutter analyze lib/widgets/hosts_dashboard.dart`
Expected: No issues found.

Run: `cd app && flutter test`
Expected: all tests pass (no behavior regression; tag search now works, label/host search unchanged).

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "feat(filter): use HostQuery for dashboard host filtering (tags now searchable)"
```

---

## Task 5: Suggestion chip bar

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (add `_toggleFacet`, render `_FacetChipBar`, add the widget class)

- [ ] **Step 1: Add the toggle handler to the State**

In `_HostsDashboardState` (next to the `_search` field), add:

```dart
  void _toggleFacet(String facet) {
    setState(() => _search = HostQuery.toggleToken(_search, facet));
  }
```

- [ ] **Step 2: Render the chip bar in the body**

In `_HostsDashboardState.build`, compute the facets just after `filtered` is defined:

```dart
    final facets = HostQuery.availableFacets(hosts);
```

Then, inside the `SingleChildScrollView`'s `Column` (the one with `crossAxisAlignment: CrossAxisAlignment.start`), insert the chip bar as the FIRST child — immediately before the `if (_search.isEmpty) ...[` Groups block:

```dart
                  if (facets.isNotEmpty) ...[
                    _FacetChipBar(
                      facets: facets,
                      query: _search,
                      onToggle: _toggleFacet,
                    ),
                    const SizedBox(height: 20),
                  ],
```

- [ ] **Step 3: Add the `_FacetChipBar` widget**

At the end of `app/lib/widgets/hosts_dashboard.dart` (top-level, after the last existing class), add:

```dart
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
    final active =
        query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: facets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final facet = facets[i];
          final on = active.contains(facet.toLowerCase());
          return GestureDetector(
            onTap: () => onToggle(facet),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: on ? AppColors.accent : AppColors.border),
              ),
              child: Text(
                facet,
                style: TextStyle(
                  color: on ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Verify the chip-bar render logic with a pure widget test**

The chip *toggle* logic is already covered by `HostQuery.toggleToken` unit tests
(Task 3). Here we only verify `_FacetChipBar` renders chips and reports taps —
no `HostProvider` wiring needed, avoiding fragile provider construction in tests.

To make `_FacetChipBar` reachable from a test, expose it via a thin public
wrapper at the bottom of `app/lib/widgets/hosts_dashboard.dart`:

```dart
/// Test-only entry point to the private facet chip bar.
@visibleForTesting
Widget facetChipBarForTest({
  required List<String> facets,
  required String query,
  required void Function(String) onToggle,
}) =>
    _FacetChipBar(facets: facets, query: query, onToggle: onToggle);
```

Add this import at the top of `hosts_dashboard.dart` if not already present:

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

Create `app/test/widgets/facet_chip_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';

void main() {
  testWidgets('renders a chip per facet and reports taps', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: facetChipBarForTest(
          facets: const ['env:prod', 'role:db'],
          query: 'env:prod',
          onToggle: (f) => tapped = f,
        ),
      ),
    ));

    expect(find.text('env:prod'), findsOneWidget);
    expect(find.text('role:db'), findsOneWidget);

    await tester.tap(find.text('role:db'));
    expect(tapped, 'role:db');
  });
}
```

- [ ] **Step 5: Run the widget test**

Run: `cd app && flutter test test/widgets/facet_chip_bar_test.dart`
Expected: PASS (2 chips found, tap reported).

- [ ] **Step 6: Verify full suite + analyzer**

Run: `cd app && flutter analyze`
Expected: No issues found.

Run: `cd app && flutter test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart app/test/widgets/facet_chip_bar_test.dart
git commit -m "feat(filter): add toggleable facet suggestion chips to hosts dashboard"
```

---

## Task 6: Tag editor hint

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart` (the tags `TextField`, ~line 196)

- [ ] **Step 1: Update the hint string**

In `app/lib/widgets/host_detail_panel.dart`, find the tags field hint:

```dart
                      hint: 'Tags (comma separated)',
```

Replace with:

```dart
                      hint: 'Tags, e.g. env:prod, role:db',
```

- [ ] **Step 2: Verify analyzer + full suite**

Run: `cd app && flutter analyze`
Expected: No issues found.

Run: `cd app && flutter test`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart
git commit -m "docs(filter): hint key:value tag convention in host detail editor"
```

---

## Done criteria

- `HostQuery` unit tests cover parse, matches (faceted OR/AND, free-text AND, case-insensitivity, malformed tokens), `availableFacets`, `toggleToken`.
- Dashboard search parses faceted queries; tags are now matchable; chip bar toggles facets into the query and highlights active ones.
- `flutter analyze` clean; full `flutter test` green.
- No `Host` schema / sync / SSH changes. `host_list.dart` left untouched (noted as dead code for a future cleanup).
