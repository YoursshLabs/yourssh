#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/../assets/native/macos"
mkdir -p "$OUT"

clang -shared -fPIC -O2 \
  -DCONFIG_VERSION='"2024-01-13"' \
  -DCONFIG_BIGNUM \
  -I "$DIR/quickjs" \
  "$DIR/quickjs/quickjs.c" \
  "$DIR/quickjs/libunicode.c" \
  "$DIR/quickjs/libregexp.c" \
  "$DIR/quickjs/cutils.c" \
  "$DIR/quickjs/libbf.c" \
  "$DIR/bridge/qjs_bridge.c" \
  -o "$OUT/libqjsbridge.dylib"

echo "Built: $OUT/libqjsbridge.dylib"
