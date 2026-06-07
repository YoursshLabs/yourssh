#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/rust"
cargo build --release
cd ..
case "$(uname -s)" in
  Darwin)
    mkdir -p assets/native/macos
    cp rust/target/release/libyourssh_rdp.dylib assets/native/macos/ ;;
  Linux)
    mkdir -p assets/native/linux
    cp rust/target/release/libyourssh_rdp.so assets/native/linux/ ;;
esac
echo "yourssh_rdp native library built"
