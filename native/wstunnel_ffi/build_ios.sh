#!/usr/bin/env bash
# Build WstunnelFFI.xcframework for device (arm64) + Simulator (arm64 + x86_64).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
cd "$ROOT"

DEVICE_TARGET=aarch64-apple-ios
SIM_ARM_TARGET=aarch64-apple-ios-sim
SIM_X86_TARGET=x86_64-apple-ios

ensure_target() {
  local t="$1"
  if ! rustup target list --installed | grep -qx "$t"; then
    echo "Installing Rust target $t…"
    rustup target add "$t"
  fi
}

ensure_target "$DEVICE_TARGET"
ensure_target "$SIM_ARM_TARGET"
ensure_target "$SIM_X86_TARGET"

echo "Building wstunnel_ffi for $DEVICE_TARGET (release)…"
cargo build --release --target "$DEVICE_TARGET"

echo "Building wstunnel_ffi for $SIM_ARM_TARGET (release)…"
cargo build --release --target "$SIM_ARM_TARGET"

echo "Building wstunnel_ffi for $SIM_X86_TARGET (release)…"
cargo build --release --target "$SIM_X86_TARGET"

LIB_DEVICE="$CARGO_TARGET_DIR/$DEVICE_TARGET/release/libwstunnel_ffi.a"
LIB_SIM_ARM="$CARGO_TARGET_DIR/$SIM_ARM_TARGET/release/libwstunnel_ffi.a"
LIB_SIM_X86="$CARGO_TARGET_DIR/$SIM_X86_TARGET/release/libwstunnel_ffi.a"

OUT="$REPO/ios/ThirdParty/WstunnelFFI"
SIM_DIR="$OUT/build/ios-simulator"
mkdir -p "$OUT/include" "$SIM_DIR"
rm -rf "$OUT/WstunnelFFI.xcframework"

# Universal simulator static lib (Apple Silicon + Intel simulators)
LIB_SIM="$SIM_DIR/libwstunnel_ffi.a"
echo "Creating universal simulator library…"
lipo -create "$LIB_SIM_ARM" "$LIB_SIM_X86" -output "$LIB_SIM"

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
  -library "$LIB_DEVICE" \
  -headers "$OUT/include" \
  -library "$LIB_SIM" \
  -headers "$OUT/include" \
  -output "$OUT/WstunnelFFI.xcframework"

echo "Wrote $OUT/WstunnelFFI.xcframework"
ls -la "$OUT/WstunnelFFI.xcframework"
/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries' \
  "$OUT/WstunnelFFI.xcframework/Info.plist" 2>/dev/null || true
