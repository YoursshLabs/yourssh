# Contributing

## Development Setup

1. Fork the repository and clone locally.
2. Follow the [Build](Developer-Guide-Build) guide to get the app running.
3. Create a feature branch from `develop`:

```bash
git checkout develop
git pull origin develop
git checkout -b feat/my-feature
```

## PR Checklist

Before opening a PR to `develop`:

- [ ] `flutter analyze` passes with no errors
- [ ] `flutter test` passes
- [ ] New features have tests in `app/test/`
- [ ] `CHANGELOG.md` updated — add an entry under `[Unreleased]`
- [ ] Relevant `docs/wiki/` page updated (or new page added)

## Wiki Updates

**Every PR that ships or modifies a user-visible feature must include a `docs/wiki/` update.**

- Existing feature changed → update the relevant `User-Guide-*.md` page
- New feature → create a new `User-Guide-*.md` page and add a row to `Home.md`
- New developer component → update or create a `Developer-Guide-*.md` page

Wiki pages are synced to GitHub Wiki automatically when the PR merges to `master`.

## Merging to master

PRs to `develop` are merged by the maintainer once CI passes. Periodic merges from `develop` → `master` cut a release. Before merging to `master`:

1. Move `[Unreleased]` → `[x.y.z]` in `CHANGELOG.md`
2. Add a fresh `[Unreleased]` block
3. Bump the version in `app/pubspec.yaml`
4. Update `docs/roadmap.md` via the `/yourssh-roadmap` skill
5. Confirm all `docs/wiki/` pages reflect the shipped state

The GitHub Action at `.github/workflows/wiki-sync.yml` syncs `docs/wiki/` to GitHub Wiki automatically on merge.

## Commit Style

```
feat(scope): add X
fix(scope): correct Y
docs(wiki): update Z page
refactor(scope): simplify W
test(scope): add tests for V
```

## Related Pages

- [Build](Developer-Guide-Build) — prerequisites and build commands
- [Architecture](Developer-Guide-Architecture) — understand the codebase
