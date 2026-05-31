# Smart Filter + Faceted Query — Design

> Status: approved (brainstorm) · date: 2026-05-31 · roadmap: P0 #1

## Goal

Make a 50+ host list navigable from the hosts dashboard with a query syntax like
`env:prod role:db region:sg` plus free-text, backed by suggestion chips. Tags
already exist on the `Host` model and are editable; the dashboard search box,
however, only matches `label` / `host` / `username` today (its hint already
claims "or tags" but the code does not honor it). This feature closes that gap
and adds faceted querying.

## Scope

**In scope**
- A pure Dart query parser + matcher (`lib/util/host_query.dart`), unit-tested.
- Wiring it into the hosts dashboard search box (replacing the current
  `label/host/username` `.contains` filter).
- A suggestion-chip row under the search box that toggles facet conditions.
- Updating the host-detail tags hint to document the `key:value` convention.

**Out of scope (noted, not done here)**
- `host_list.dart` (`HostListPanel`) appears unused — never mounted anywhere.
  It still wires `HostProvider.setSearch`. Candidate for deletion in a separate
  cleanup; not touched here.
- No change to `Host` schema, sync payload, or SSH logic.
- `HostProvider.hosts` / `setSearch` left as-is (still referenced by
  `port_forwarding_screen.dart`); the dashboard switches to `allHosts`.

## Tag convention

`Host.tags` remains `List<String>`. By convention each entry is `key:value`
(e.g. `env:prod`, `role:db`). Entries without a `:` are still valid — treated as
valueless labels, matched only via free-text. No migration needed; existing
plain tags keep working.

## Parser + matcher — `lib/util/host_query.dart`

Pure Dart, no Flutter imports, so it is unit-testable in isolation.

### Parsing — `HostQuery.parse(String raw) -> HostQuery`

- Split `raw` on whitespace into tokens.
- A token is a **facet** `(key, value)` iff it contains `:` AND both sides of
  the first `:` are non-empty. Key and value are lower-cased.
- Every other token (including malformed ones like `env:` or `:prod`) is a
  **free-text term**, lower-cased.
- Result holds: `Map<String, Set<String>> facets` (key → set of values) and
  `List<String> terms`.

### Matching — `HostQuery.matches(Host host) -> bool`

Empty query (no facets, no terms) → `true`.

1. **Facets** — for each `key` group:
   - Host matches the group iff at least one of its tags equals `key:value`
     (case-insensitive, exact) for **some** value in the group → **OR within a
     key**.
   - The host must match **every** key group → **AND across keys**.
2. **Free-text terms** — each term must be a case-insensitive substring of
   `label`, `host`, `username`, OR any tag's value (the part after `:`, or the
   whole tag if it has no `:`). All terms must match → **AND**.
3. Host passes iff facet check AND free-text check both pass.

### Helper — `HostQuery.availableFacets(List<Host>) -> List<String>`

Returns the distinct `key:value` tags across all hosts (deduped,
case-insensitive, sorted) — used to render suggestion chips.

## Dashboard UI — `hosts_dashboard.dart`

- The existing search `TextField` text feeds `HostQuery.parse`. The current
  filter block (`hosts.where(label/host/username contains query)`) is replaced
  by `allHosts.where(query.matches)`.
- Source switches from `hostProvider.hosts` to `hostProvider.allHosts`.
- **Suggestion chips:** a horizontally-scrollable row beneath the search box,
  one chip per `availableFacets(allHosts)` entry, plus the existing pinned
  groups if useful. Tapping a chip toggles its `key:value` token in the query
  string (append if absent, remove if present). Active chips are highlighted
  (reuse `AppColors.accent`). Chips are derived from `allHosts` so they reflect
  real data; if the set is large the row scrolls (no artificial cap).
- The group cards / pinned-group logic above the host grid is unchanged.

## Tag editor — `host_detail_panel.dart`

No behavior change. Update the tags field hint from
`Tags (comma separated)` to `Tags, e.g. env:prod, role:db` to teach the
convention. Storage stays comma-separated free text.

## Error handling / edge cases

- Malformed facet tokens (`env:`, `:prod`, `a:b:c`) → `a:b:c` splits on the
  first `:` → facet `(a, b:c)`; `env:`/`:prod` have an empty side → demoted to
  free-text term. No exceptions thrown.
- Whitespace-only query → empty `HostQuery` → matches all.
- Duplicate facet values in the query collapse via the `Set`.

## Testing

Unit tests for `host_query.dart` (`test/util/host_query_test.dart`):
- empty / whitespace query matches all
- single facet exact match; non-match
- same key OR (`env:prod env:staging`)
- different keys AND (`env:prod role:db`)
- free-text substring across label/host/username/tag-value
- case-insensitivity (query and tags in mixed case)
- malformed tokens demote to free-text, no throw
- `availableFacets` dedupes and sorts

Optional widget test: tapping a suggestion chip appends the token and filters
the grid; tapping again removes it.

## Files touched

| File | Change |
|------|--------|
| `lib/util/host_query.dart` | **new** — parser + matcher + `availableFacets` |
| `lib/widgets/hosts_dashboard.dart` | use `allHosts` + `HostQuery`; add chip row |
| `lib/widgets/host_detail_panel.dart` | tags hint text only |
| `test/util/host_query_test.dart` | **new** — unit tests |
