# wstunnel_ffi

C ABI wrapper around [wstunnel](https://github.com/erebe/wstunnel) **10.5.2** for the iOS Packet Tunnel extension.

## Build XCFramework (device)

```bash
./build_ios.sh
```

Produces `ios/ThirdParty/WstunnelFFI/WstunnelFFI.xcframework` (arm64).

Requires Rust with target `aarch64-apple-ios` and Xcode `xcodebuild`.

Vendored sources live in `native/vendor/wstunnel-10.5.2` (path dependency in `Cargo.toml`).
