#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
OUT_JNI="$REPO/android/app/src/main/jniLibs"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"

# Prefer Flutter/Android Studio NDK if ANDROID_NDK_HOME unset.
if [[ -z "${ANDROID_NDK_HOME:-}" && -z "${NDK_HOME:-}" ]]; then
  if [[ -d "$HOME/Library/Android/sdk/ndk" ]]; then
    # Pick newest installed NDK.
    ANDROID_NDK_HOME="$(ls -1d "$HOME/Library/Android/sdk/ndk"/* | sort -V | tail -1)"
    export ANDROID_NDK_HOME
  fi
fi

if [[ -z "${ANDROID_NDK_HOME:-}${NDK_HOME:-}" ]]; then
  echo "ANDROID_NDK_HOME (or NDK_HOME) is required" >&2
  exit 1
fi

cd "$ROOT"
NDK_PATH="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
echo "Building wstunnel_ffi for Android (arm64-v8a, armeabi-v7a) with NDK=${NDK_PATH}..."
cargo ndk -t arm64-v8a -t armeabi-v7a -o "$OUT_JNI" build --release

echo "Wrote:"
find "$OUT_JNI" -name 'libwstunnel_ffi.so' -print
