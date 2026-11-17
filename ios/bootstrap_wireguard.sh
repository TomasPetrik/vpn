#!/usr/bin/env bash
# Clone/patch wireguard-apple and wire it into Runner.xcodeproj.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$ROOT/ThirdParty/wireguard-apple"

mkdir -p "$ROOT/ThirdParty"
if [[ ! -d "$DEST/.git" ]]; then
  git clone --depth 1 https://git.zx2c4.com/wireguard-apple "$DEST"
fi

# Official Package.swift uses tools-version 5.3 but platforms need 5.5+.
sed -i '' 's|^// swift-tools-version:.*|// swift-tools-version:5.9|' "$DEST/Package.swift"

# Xcode 16+/iOS 27 SDK: BSD types must be imported before use in WireGuardKitC.
HDR="$DEST/Sources/WireGuardKitC/WireGuardKitC.h"
if ! grep -q '#include <sys/types.h>' "$HDR"; then
  sed -i '' '/Copyright/a\
\
#include <sys/types.h>
' "$HDR"
fi

ruby "$ROOT/add_wireguard_kit.rb"
echo "WireGuardKit bootstrap OK. Ensure Go is on PATH (go version)."
