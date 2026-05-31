---
name: yourssh-refactor-sweep
description: Use when the user wants to review and refactor/optimize functions across the yourssh codebase — e.g. "review và refactor", "tối ưu code", "clean up duplication", "find dead code", or a broad "optimize the whole project" request scoped to app/lib or packages/.
---

# YourSSH Refactor Sweep

Review the Flutter codebase for optimization opportunities and apply the **safe, behavior-preserving** ones. Optimize for high-confidence wins; defer risky changes for explicit sign-off.

## When to use

- User asks to "review và refactor", "tối ưu", "clean up", "find dead code" over an area or the whole project.
- After a feature lands and the code needs a tidy pass.

**Do not use when:** the user wants a single targeted bug fix (use `superpowers:systematic-debugging`) or a behavioral change/new feature (use `superpowers:brainstorming`).

## Four categories to scan

1. **Performance** — excess `notifyListeners()`, work in `build()`/getters called per frame, repeated I/O, O(n) lookups that should be a `Map`/`Set`, redundant parsing.
2. **Duplication** — repeated logic → shared helper/extension/top-level function.
3. **Readability** — long functions, deep nesting, huge `build()` → split into methods or extracted widgets.
4. **Dead code** — unused private methods/fields/imports, unreachable branches.

## Workflow

1. **Scope first.** If the request is broad, use `AskUserQuestion` to pin down: which categories, and which area (`app/lib/services`, `app/lib/providers`, whole `app/lib`, or `packages/`). Don't sweep blind — it burns tokens.

2. **Map size.** `find app/lib -name '*.dart' | xargs wc -l | sort -rn | head -40` to find the heavy files.

3. **Fan out (parallel).** Dispatch `Explore` subagents — one per area (services / providers / widgets) — to return concrete findings: `file:line` + category + one-line problem + suggested fix. Tell them: high-confidence only, no style nitpicks, prioritize by impact.

4. **Filter to safe wins.** Apply ONLY behavior-preserving changes. Verify each finding by reading the actual code before editing (agents over-report). Good defaults:
   - Merge identical methods; extract repeated predicates/loops into a helper.
   - Guard `notifyListeners()` with an equality check (`if (_x == v) return;`).
   - Replace long `switch`/`.any()` per-frame scans with `Map`/`Set` lookups.
   - Extract a large `ListView.builder` row into a `StatelessWidget` (better element reuse); split a >150-line `build()` into private `_buildX` methods or sub-widgets.
   - Pull repeated `InputDecoration`/styling into a helper.

5. **Defer risky changes** — surface them in the summary instead of doing them silently: public API/signature changes (e.g. connection pooling), widget splits tangled with lifecycle state (`didUpdateWidget`, post-frame callbacks), anything that could shift behavior.

6. **Verify before claiming done** (mandatory): `cd app && flutter analyze` → must be clean, then `flutter test` → all pass. Never report success without both.

## Output

Group applied changes by category with `file:line`. List deferred high-value items separately with the reason they need sign-off. Ask before doing the risky batch.

## Notes

- Repo output (code, comments) is English-only; chat replies in Vietnamese.
- Keep edits idiomatic to surrounding code (match naming, comment density).
