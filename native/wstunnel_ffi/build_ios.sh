#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
cd "$ROOT"

echo "Building wstunnel_ffi for aarch64-apple-ios (release)…"
cargo build --release --target aarch64-apple-ios

LIB="$CARGO_TARGET_DIR/aarch64-apple-ios/release/libwstunnel_ffi.a"
OUT="$REPO/ios/ThirdParty/WstunnelFFI"
rm -rf "$OUT/WstunnelFFI.xcframework"
mkdir -p "$OUT/include"
cat > "$OUT/include/wstunnel_ffi.h" <<'EOF'
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int wstunnel_client_start(const char *config_json, char *err_buf, size_t err_len);
void wstunnel_client_stop(void);
int wstunnel_client_is_running(void);

#ifdef __cplusplus
}
#endif
EOF
cat > "$OUT/include/module.modulemap" <<'EOF'
module WstunnelFFI {
  header "wstunnel_ffi.h"
  export *
}
EOF

xcodebuild -create-xcframework \
  -library "$LIB" \
  -headers "$OUT/include" \
  -output "$OUT/WstunnelFFI.xcframework"

echo "Wrote $OUT/WstunnelFFI.xcframework"
