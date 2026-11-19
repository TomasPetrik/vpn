# wstunnel_ffi

C ABI wrapper around [wstunnel](https://github.com/erebe/wstunnel) **10.5.2** for the iOS Packet Tunnel extension.

## Build XCFramework (device + Simulator)

```bash
./build_ios.sh
```

Produces `ios/ThirdParty/WstunnelFFI/WstunnelFFI.xcframework` with:

- `ios-arm64` — physical devices
- `ios-arm64_x86_64-simulator` — Simulator (Apple Silicon + Intel)

Requires Rust targets `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`, and Xcode `xcodebuild` / `lipo`.

Vendored sources live in `native/vendor/wstunnel-10.5.2` (path dependency in `Cargo.toml`).

> Packet Tunnel / Network Extension still cannot fully run VPN on the Simulator; the sim slice mainly lets the app **build and launch** there for UI work.
