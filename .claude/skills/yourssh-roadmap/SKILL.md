---
name: yourssh-roadmap
description: Use when the user wants to refresh, update, or regenerate the yourssh project roadmap at docs/roadmap.md — e.g. after shipping a feature, bumping version, completing a sprint, or asking "cập nhật roadmap"
---

# YourSSH Roadmap Refresh

Update `docs/roadmap.md` for the yourssh repo based on the actual state of the codebase + git history. Avoid rewriting the roadmap from scratch each time — only diff what already exists and propose new features.

## When to use

- User says "update roadmap", "refresh roadmap", "cập nhật roadmap", "version bump xong rồi"
- After merging a large feature into develop/master
- When prepping for sprint planning
- When the version in `app/pubspec.yaml` changes

**Do not use when:** the user wants to brainstorm completely new features from scratch (use `superpowers:brainstorming`) or write a spec for a specific feature (use `superpowers:writing-plans`).

## Workflow

1. **Read current state** (run in parallel):
   - `Read docs/roadmap.md` — existing roadmap
   - `Bash git log --oneline -30` — recent commits
   - `Bash grep -E "^version:" app/pubspec.yaml` — current version
   - `Bash ls app/lib/providers app/lib/services app/lib/widgets packages/` — surface area of existing code
   - `Bash git tag --sort=-creatordate | head -10` — shipped releases

2. **Classify shipped vs remaining** by comparing commit messages + new file names against the old roadmap list. Move shipped bullets up to the "Shipped" section at the top of the doc.

3. **Update metadata**:
   - Version line: `Current version: X.Y.Z`
   - Date line: `updated: YYYY-MM-DD` (use the real date, do not hard-code)

4. **Ask the user one question** (via `AskUserQuestion`):
   - Are there new features to add to P0/P1/P2?
   - Is there anything to re-prioritize?
   - If the user says "no, just update what's shipped" → skip step 5.

5. **Apply user changes** (if any) into the correct table/section.

6. **Show diff before committing**: `Bash git diff docs/roadmap.md`. Wait for user approval before suggesting a commit.

## Roadmap structure (must be preserved)

```
# YourSSH — Roadmap
> Direction + version + date
[Section "Shipped"]
## P0 — Must-have to retain power users  (table with 10 rows)
## P1 — Differentiation & DevOps depth  (sub-sections by theme)
## P2 — Team / Enterprise
## Top 3 suggestions for the next sprint
## How to use this document
```

Do not change the structure unless the user requests it. P0 is always a table (Feature / Purpose / Implementation notes). P1 is always split by theme.

## Detection heuristics — "has this feature shipped?"

| Feature in roadmap | Check |
|---|---|
| Command Palette | `grep -r "CommandPalette\|command_palette" app/lib/` |
| Tag/group | `grep -E "tags\s*:" app/lib/models/host.dart` |
| SSH config import | `grep -r "ssh_config\|parseSSHConfig" app/lib/` |
| Workspace persistence | `grep -r "workspace\|restoreSession" app/lib/providers/` |
| Search-in-scrollback | `grep -r "searchBuffer\|scrollback.*search" app/lib/` |
| Kubernetes panel | `ls packages/ \| grep -i kube` |

When grep returns a real match (not a comment/TODO), consider it shipped → move to "Shipped".

## Common mistakes

- ❌ Re-generating the entire roadmap from scratch → loses user-added notes from previous sessions. **Always read first, edit in place.**
- ❌ Hard-coding the date in the skill. **Always Bash `date +%Y-%m-%d`.**
- ❌ Committing without showing the diff. **Always show diff and wait for approval.**
- ❌ Skipping `packages/` when detecting shipped features — the plugin folder counts too.
- ❌ Changing section/table format structure → makes diffs between versions harder to read.
- ❌ Forgetting to update the wiki when shipping a feature. **Always update `docs/wiki/` alongside `docs/roadmap.md`:**
  - User-visible feature shipped → update or create `docs/wiki/User-Guide-*.md`
  - New developer component → update `docs/wiki/Developer-Guide-*.md`
  - New feature area → add a row to `docs/wiki/Home.md`

## Output

Edit file `docs/roadmap.md` in place (do not create a new file). At the end, output a 2–3 line summary:
- How many items were moved to "Shipped"
- How many new items were added
- Suggested commit message (but do not commit automatically).
