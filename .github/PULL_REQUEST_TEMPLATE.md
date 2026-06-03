<!--
PR title must follow Conventional Commits:
  feat(scope): ... | fix(scope): ... | docs(scope): ... | test(scope): ... | refactor(scope): ... | release: x.y.z
-->

## Summary

<!-- What does this PR do and why? 1–3 sentences. -->

## Changes

<!-- Bullet list of notable changes. -->

-

## Type of change

- [ ] `feat` — new feature
- [ ] `fix` — bug fix
- [ ] `refactor` / `polish` — no behavior change
- [ ] `docs` — documentation only
- [ ] `test` — tests only
- [ ] `release` — version release to `master`

## How was this tested?

<!-- Commands run and manual steps. Paste relevant output if useful. -->

- [ ] `cd app && flutter analyze` — no new warnings
- [ ] `cd app && flutter test` — all tests pass
- [ ] Manually verified on: <!-- macOS / Windows / Linux -->

## Screenshots

<!-- Required for UI changes. Delete this section if not applicable. -->

## Checklist

- [ ] PR title follows Conventional Commits
- [ ] Code and comments are written in English
- [ ] New/changed behavior is covered by tests
- [ ] No secrets, credentials, or personal data in the diff

### Required when targeting `master` (release PRs)

- [ ] `CHANGELOG.md` updated — `[Unreleased]` moved to a versioned section, fresh `[Unreleased]` block added, comparison links updated
- [ ] Version bumped in `app/pubspec.yaml`
- [ ] `README.md` / `CLAUDE.md` updated if architecture or features changed
- [ ] `docs/roadmap.md` updated
- [ ] Wiki release notes prepared
