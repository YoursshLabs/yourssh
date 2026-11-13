#!/usr/bin/env bash
# Builds and runs the docs screenshot journey with FULL isolation.
#   tool/docs_journey.sh [setup|build|run|all|teardown]    (default: all)
#     setup     generate a client key, build the demo image, create the network and 5 demo containers (idempotent)
#     build     build the integration-test macOS app
#     run       launch the app against the demo containers, capture PNGs
#     all       build + run (containers must already exist: run `setup` first)
#     teardown  stop + remove only the containers/network/image created by `setup`
# The integration-test app is built once with the real HOME (flutter tool needs
# it), then the built binary is launched directly with HOME=<temp demo home>.
# Env: SECTIONS="01,02,..." limits sections; MODES="desktop mobile" picks launches;
#      DOCS_OUT overrides the output dir; DOCS_KEY_DIR holds the generated client key
#      (default ~/.local/state/yourssh-docs-journey, never inside the repo).
#      DOCS_PREFIX (default yourssh-docs) names containers/network/image;
#      SSH_PORT/BASTION_PORT/RDP_PORT/VNC_PORT override host ports. The app harness
#      expects the defaults 2222/2223/3389/5900, so override them only to test setup.
set -euo pipefail
command -v flutter >/dev/null 2>&1 || export PATH="$HOME/development/flutter/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-all}"
OUT="${DOCS_OUT:-$ROOT/screenshots/docs}"
PREFIX="${DOCS_PREFIX:-yourssh-docs}"
SSH_PORT="${SSH_PORT:-2222}"; BASTION_PORT="${BASTION_PORT:-2223}"
RDP_PORT="${RDP_PORT:-3389}"; VNC_PORT="${VNC_PORT:-5900}"
KEY_DIR="${DOCS_KEY_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/yourssh-docs-journey}"
KEY="$KEY_DIR/client_ed25519"
NET="$PREFIX-net"; IMAGE="$PREFIX-ssh:latest"
CONTAINERS=("$PREFIX-ssh" "$PREFIX-bastion" "$PREFIX-db" "$PREFIX-rdp" "$PREFIX-vnc")

is_running() { [[ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]; }
exists() { docker container inspect "$1" >/dev/null 2>&1; }
ensure() { # name, then `docker run` args: reuse a running one, start a stopped one, else create
  local n="$1"; shift
  if is_running "$n"; then echo "reuse running $n"
  elif exists "$n"; then echo "start $n"; docker start "$n" >/dev/null
  else echo "create $n"; docker run -d --name "$n" "$@" >/dev/null; fi
}

setup() {
  mkdir -p "$KEY_DIR"; chmod 700 "$KEY_DIR"
  [[ -f "$KEY" ]] || ssh-keygen -q -t ed25519 -N '' -C yourssh-docs-demo -f "$KEY"
  docker build -q -t "$IMAGE" "$ROOT/tool/docs_journey" >/dev/null
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
  ensure "$PREFIX-ssh" --network "$NET" --network-alias yourssh-demo --hostname yourssh-demo -p "127.0.0.1:$SSH_PORT:22" "$IMAGE"
  ensure "$PREFIX-bastion" --network "$NET" --network-alias bastion --hostname bastion -p "127.0.0.1:$BASTION_PORT:22" "$IMAGE"
  ensure "$PREFIX-db" --network "$NET" --network-alias db-internal --hostname db-internal "$IMAGE"
  local c
  for c in ssh bastion db; do # install the client public key (idempotent overwrite)
    docker exec -i "$PREFIX-$c" sh -c 'cat > /home/demo/.ssh/authorized_keys && chown demo:demo /home/demo/.ssh/authorized_keys && chmod 600 /home/demo/.ssh/authorized_keys' < "$KEY.pub"
  done
  ensure "$PREFIX-rdp" --hostname win-demo -p "127.0.0.1:$RDP_PORT:3389" scottyhardy/docker-remote-desktop:latest
  ensure "$PREFIX-vnc" -e VNC_PW=demo12345 -p "127.0.0.1:$VNC_PORT:5900" dorowu/ubuntu-desktop-lxde-vnc:latest
  # RDP login demo / demo12345 (idempotent)
  for _ in $(seq 1 20); do docker exec "$PREFIX-rdp" true 2>/dev/null && break; sleep 1; done
  docker exec "$PREFIX-rdp" bash -c "id demo >/dev/null 2>&1 || useradd -m -s /bin/bash demo; echo 'demo:demo12345' | chpasswd"
  echo "setup done. client key: $KEY (host ports ssh=$SSH_PORT bastion=$BASTION_PORT rdp=$RDP_PORT vnc=$VNC_PORT)"
}

teardown() {
  local c
  for c in "${CONTAINERS[@]}"; do exists "$c" && { docker rm -f "$c" >/dev/null; echo "removed $c"; }; done
  docker network inspect "$NET" >/dev/null 2>&1 && { docker network rm "$NET" >/dev/null; echo "removed network $NET"; }
  docker image inspect "$IMAGE" >/dev/null 2>&1 && { docker rmi "$IMAGE" >/dev/null; echo "removed image $IMAGE"; }
  echo "teardown done (client key in $KEY_DIR kept; delete it manually if unwanted)"
}

case "$MODE" in
  setup) setup; exit 0 ;;
  teardown) teardown; exit 0 ;;
  build|run|all) ;;
  *) echo "usage: $0 [setup|build|run|all|teardown]" >&2; exit 2 ;;
esac
RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/yourssh-docs-run.XXXXXX")"
DEMO_HOME="$RUN_ROOT/yourssh-docs-home"

if [[ "$MODE" == build || "$MODE" == all ]]; then
  (cd "$ROOT/app" && flutter build macos --debug -t integration_test/docs_journey_test.dart)
fi
[[ "$MODE" == build ]] && exit 0
[[ -f "$KEY" ]] || { echo "no client key at $KEY: run '$0 setup' first" >&2; exit 1; }
for c in "${CONTAINERS[@]}"; do is_running "$c" || { echo "$c is not running: run '$0 setup' first" >&2; exit 1; }; done

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
  # ...and so is one whose shots are not phone-sized (390x844 @2x = 780 px wide).
  if [[ "$m" == mobile ]]; then
    W="$(sips -g pixelWidth "$OUT/M1-mobile/02-hosts.png" 2>/dev/null | awk '/pixelWidth/{print $2}')"
    N="$(ls "$OUT"/M1-mobile/*.png 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$N" -lt 14 || "$W" != 780 ]]; then
      echo "mobile run produced $N shots at width ${W:-none}; retrying once"; launch mobile
    fi
  fi
done
cat "$OUT"/INDEX.*.part.md > "$OUT/INDEX.md" 2>/dev/null || true
rm -f "$OUT"/INDEX.*.part.md

AFTER_PLIST="$(stat -f '%m' "$HOME/Library/Preferences/com.thangnm.yourssh.plist" 2>/dev/null || echo none)"
AFTER_DIR="$(find "$HOME/.yourssh" -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum | cut -d' ' -f1)"
echo "ISOLATION after:  plist_mtime=$AFTER_PLIST yourssh_dir_hash=$AFTER_DIR"
[[ "$BEFORE_PLIST" == "$AFTER_PLIST" && "$BEFORE_DIR" == "$AFTER_DIR" ]] && echo "ISOLATION OK" || echo "ISOLATION VIOLATED"
echo "run logs: $RUN_ROOT/run-*.log"
