#!/usr/bin/env bash
# Fails if an iOS .app bundle contains desktop-only pieces that must never ship
# on iOS: the QuickJS bridge, the Rust RDP/VNC libraries, the flutter_pty
# fork (forkpty is not allowed in an App Store build), or an ATS opt-out.
# Usage: tool/check_ios_bundle.sh <path to Runner.app>
set -u

app="${1:-}"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "usage: $0 <path to .app bundle>" >&2
  exit 2
fi

fail=0

names=$(find "$app" \( -name '*qjsbridge*' -o -name '*libquickjs*' \
  -o -name '*yourssh_rdp*' -o -name '*yourssh_vnc*' -o -name '*flutter_pty*' \) -print)
if [ -n "$names" ]; then
  echo "FAIL: forbidden files or directories in the bundle:" >&2
  echo "$names" >&2
  fail=1
fi

syms=$(grep -a -r -l 'pty_forkpty' "$app" 2>/dev/null)
if [ -n "$syms" ]; then
  echo "FAIL: files carrying the pty_forkpty symbol:" >&2
  echo "$syms" >&2
  fail=1
fi

if [ -f "$app/Info.plist" ] && grep -a -q 'NSAllowsArbitraryLoads' "$app/Info.plist"; then
  echo "FAIL: Info.plist contains NSAllowsArbitraryLoads" >&2
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK: $app"
exit "$fail"
