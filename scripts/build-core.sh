#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
OUT="$ROOT/macos/YourSSH/Generated"
LIB_OUT="$ROOT/macos/YourSSH/Libs"

mkdir -p "$OUT" "$LIB_OUT"

echo "▶ Building Rust core (Apple Silicon)..."
cd "$CORE"
source ~/.cargo/env
cargo build --release --target aarch64-apple-darwin

echo "▶ Building Rust core (Intel)..."
cargo build --release --target x86_64-apple-darwin

echo "▶ Creating universal binary..."
lipo -create \
    "target/aarch64-apple-darwin/release/libyourssh_core.a" \
    "target/x86_64-apple-darwin/release/libyourssh_core.a" \
    -output "$LIB_OUT/libyourssh_core.a"

echo "▶ Generating Swift bindings..."
cargo run --bin uniffi_bindgen -- generate \
    src/yourssh.udl \
    --language swift \
    --out-dir "$OUT"

# Copy header for Xcode
cp "$OUT/yoursshFFI.h" "$LIB_OUT/yoursshFFI.h"
cp "$OUT/yoursshFFI.modulemap" "$LIB_OUT/module.modulemap"

echo "✓ Done!"
echo "  Library : $LIB_OUT/libyourssh_core.a  ($(du -sh "$LIB_OUT/libyourssh_core.a" | cut -f1))"
echo "  Bindings: $OUT/yourssh.swift"
