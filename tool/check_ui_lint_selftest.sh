#!/usr/bin/env bash
# Self-test for tool/check_ui_lint.sh: plants violations in a temp tree.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/app/lib" "$tmp/tool"
lint() { UI_LINT_ALLOWLIST="$tmp/tool/allow.txt" bash "$here/check_ui_lint.sh" "$tmp" >/dev/null 2>&1; }
fail() { echo "SELFTEST FAIL: $1"; exit 1; }

: > "$tmp/tool/allow.txt"
printf 'final a = FLucideIcons.x; WtIconButton(a); SettingsIconButton(a);\n// IconButton( in a comment\n' > "$tmp/app/lib/ok.dart"
lint || fail "clean tree must pass (word boundaries / comments)"

for bad in 'IconButton(' 'AlertDialog(' 'SnackBar(' 'Icons.add' 'ScaffoldMessenger.of(c)'; do
  printf 'final w = %s;\n' "$bad" > "$tmp/app/lib/bad.dart"
  if lint; then fail "'$bad' must fail"; fi
done

printf 'final w = Icons.add;\n' > "$tmp/app/lib/bad.dart"
printf 'app/lib/bad.dart:Icons.  # selftest\n' > "$tmp/tool/allow.txt"
lint || fail "allowlisted hit must pass"
printf 'final w = AlertDialog(x);\n' > "$tmp/app/lib/bad.dart"
if lint; then fail "allowlist for another pattern must not cover AlertDialog("; fi
echo "ui lint selftest OK"
