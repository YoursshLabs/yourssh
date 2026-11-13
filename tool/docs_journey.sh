#!/usr/bin/env bash
# Builds and runs the docs screenshot journey with FULL isolation.
#   tool/docs_journey.sh [build|run|all]    (default: all)
# The integration-test app is built once with the real HOME (flutter tool needs
# it), then the built binary is launched directly with HOME=<temp demo home>.
# Env: SECTIONS="01,02,..." limits the sections; DOCS_OUT overrides the output dir.
set -euo pipefail
export PATH="$HOME/development/flutter/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-all}"
OUT="${DOCS_OUT:-$ROOT/screenshots/docs}"
RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/yourssh-docs-run.XXXXXX")"
DEMO_HOME="$RUN_ROOT/yourssh-docs-home"
KEY="${DEMO_KEY:-/private/tmp/claude-501/-Users-thangnm-Documents-Personal/249a95bd-233f-499c-b54b-eb14f3c0d9dd/scratchpad/journey/sshd/client_ed25519}"

if [[ "$MODE" == build || "$MODE" == all ]]; then
  (cd "$ROOT/app" && flutter build macos --debug -t integration_test/docs_journey_test.dart)
fi
[[ "$MODE" == build ]] && exit 0

APP="$ROOT/app/build/macos/Build/Products/Debug/yourssh.app/Contents/MacOS/yourssh"
[[ -x "$APP" ]] || APP="$(ls "$ROOT"/app/build/macos/Build/Products/Debug/*.app/Contents/MacOS/* | head -1)"

mkdir -p "$DEMO_HOME/Documents" "$DEMO_HOME/Downloads" "$DEMO_HOME/.keys-src"
printf '# Demo project\n\nSample notes for the YourSSH docs.\n' > "$DEMO_HOME/Documents/README.md"
printf 'hello from the local machine\n' > "$DEMO_HOME/Documents/notes.txt"
printf 'a,b,c\n1,2,3\n' > "$DEMO_HOME/Documents/data.csv"
printf '#!/bin/sh\necho demo\n' > "$DEMO_HOME/Documents/run-demo.command"; chmod +x "$DEMO_HOME/Documents/run-demo.command"
mkdir -p "$DEMO_HOME/Documents/photos" "$DEMO_HOME/Documents/reports"
head -c 200000 /dev/urandom > "$DEMO_HOME/Documents/backup.tar.gz"
cp "$KEY" "$DEMO_HOME/.keys-src/demo_ed25519"; [[ -f "$KEY.pub" ]] && cp "$KEY.pub" "$DEMO_HOME/.keys-src/demo_ed25519.pub" || true

BEFORE_PLIST="$(stat -f '%m' "$HOME/Library/Preferences/com.thangnm.yourssh.plist" 2>/dev/null || echo none)"
BEFORE_DIR="$(find "$HOME/.yourssh" -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum | cut -d' ' -f1)"
echo "ISOLATION before: plist_mtime=$BEFORE_PLIST yourssh_dir_hash=$BEFORE_DIR"

# cwd = repo root so the QuickJS dylib fallback (cwd/packages/...) resolves.
# Two launches: the desktop journey, then the mobile UI (DOCS_MODE=mobile).
launch() {
  pkill -f "$ROOT/app/build/macos/Build/Products/Debug/" 2>/dev/null || true; sleep 1
  (cd "$ROOT" && env HOME="$DEMO_HOME" DOCS_OUT="$OUT" DOCS_SECTIONS="${SECTIONS:-}" DOCS_MODE="$1" \
    DOCS_KEY_SRC="$DEMO_HOME/.keys-src/demo_ed25519" timeout "${LAUNCH_TIMEOUT:-1800}" "$APP" 2>&1 | tee "$RUN_ROOT/run-$1.log") || true
  pkill -f "$ROOT/app/build/macos/Build/Products/Debug/" 2>/dev/null || true
}
caffeinate -dims -w $$ >/dev/null 2>&1 &   # keep the display awake: a sleeping/occluded window stops Flutter frames
mkdir -p "$OUT"
MODES="${MODES:-desktop mobile}"
for m in $MODES; do
  launch "$m"
  # A hung/aborted mobile launch (observed once) is retried a single time.
  if [[ "$m" == mobile && "$(ls "$OUT"/M1-mobile/*.png 2>/dev/null | wc -l | tr -d ' ')" -lt 14 ]]; then
    echo "mobile run produced too few shots; retrying once"; launch mobile
  fi
done
cat "$OUT"/INDEX.*.part.md > "$OUT/INDEX.md" 2>/dev/null || true
rm -f "$OUT"/INDEX.*.part.md

AFTER_PLIST="$(stat -f '%m' "$HOME/Library/Preferences/com.thangnm.yourssh.plist" 2>/dev/null || echo none)"
AFTER_DIR="$(find "$HOME/.yourssh" -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum | cut -d' ' -f1)"
echo "ISOLATION after:  plist_mtime=$AFTER_PLIST yourssh_dir_hash=$AFTER_DIR"
[[ "$BEFORE_PLIST" == "$AFTER_PLIST" && "$BEFORE_DIR" == "$AFTER_DIR" ]] && echo "ISOLATION OK" || echo "ISOLATION VIOLATED"
echo "run logs: $RUN_ROOT/run-*.log"
