#!/usr/bin/env bash
# UI lint gate: fails on Material widgets the forui migration replaced.
#
# Scans app/lib and the plugin packages (NOT packages/yourssh_ui, which wraps
# Material where it must) for IconButton(, AlertDialog(, SnackBar(, Icons.,
# ScaffoldMessenger, showDialog(, showModalBottomSheet, TextField(. Justified remaining sites live in
# tool/ui_lint_allowlist.txt, one `path:pattern  # reason` per line (the path
# is relative to the repo root; the pattern is one of the literal tokens
# above, or `*` for every token in that file).
#
# Usage: tool/check_ui_lint.sh [repo-root]   (default: the repo this script is in)
# POSIX tools only (grep, sed, awk): runs on Linux CI and macOS.
set -eu

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
allowlist="${UI_LINT_ALLOWLIST:-$root/tool/ui_lint_allowlist.txt}"

patterns='IconButton(
AlertDialog(
SnackBar(
Icons.
ScaffoldMessenger
showDialog(
showModalBottomSheet
TextField('

dirs=""
for d in app/lib packages/yourssh_snippets/lib packages/yourssh_devops/lib packages/yourssh_web_tools/lib; do
  [ -d "$root/$d" ] && dirs="$dirs $d"
done

allowed() { # file pattern
  [ -f "$allowlist" ] || return 1
  awk -v f="$1" -v p="$2" '
    { sub(/[ \t]*#.*/, "") }
    NF == 0 { next }
    { i = index($0, ":"); if (i == 0) next
      path = substr($0, 1, i - 1); pat = substr($0, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", path); gsub(/^[ \t]+|[ \t]+$/, "", pat)
      if (path == f && (pat == "*" || pat == p)) found = 1 }
    END { exit found ? 0 : 1 }' "$allowlist"
}

status=0
cd "$root"
# shellcheck disable=SC2086
files=$(find $dirs -name '*.dart' 2>/dev/null | sort)
for f in $files; do
  echo "$patterns" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    # Left word boundary, so FLucideIcons. / WtIconButton( / SettingsIconButton(
    # / showYsDialog( / FTextField( / DevopsTextField( do not match. Comment-only lines are skipped.
    re="(^|[^A-Za-z0-9_])$(printf '%s' "$p" | sed 's/[.(]/\\&/g')"
    hits=$(grep -nE -- "$re" "$f" | grep -vE '^[0-9]+:[[:space:]]*//' || true)
    [ -n "$hits" ] || continue
    if ! allowed "$f" "$p"; then
      echo "$hits" | sed "s|^|$f:|; s|\$|   [$p]|"
      echo "FAIL" >> "${TMPDIR:-/tmp}/.ui_lint_fail.$$"
    fi
  done
done

failfile="${TMPDIR:-/tmp}/.ui_lint_fail.$$"
if [ -f "$failfile" ]; then
  rm -f "$failfile"
  echo
  echo "UI lint failed: use the yourssh_ui / forui widgets (YsButton, FButton.icon, showYsDialog, YsToast, FLucideIcons)"
  echo "or add a justified entry to tool/ui_lint_allowlist.txt."
  exit 1
fi
echo "UI lint OK"
