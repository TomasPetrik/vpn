# 0006: Native VPN engine with an embedded wstunnel client

Status: Proposed (pending the Phase 2 spikes)

## Context

Flutter cannot create VPN tunnels; that needs Android `VpnService` and an iOS Packet Tunnel Network Extension. The official WireGuard embedding libraries are `com.wireguard.android:tunnel` and WireGuardKit. Neither supports wstunnel. wstunnel ships no mobile library: the `wstunnel` Rust crate exposes client entrypoints, but nothing is packaged for mobile. The Flutter plugin `wireguard_flutter` is stale and has no wstunnel support.

## Decision

- Write a small in-app native bridge (MethodChannel `vpn_engine` + EventChannel `vpn_engine/status`) instead of a pub.dev VPN plugin.
- **WireGuard:** `GoBackend` on Android; WireGuardKit inside a `PacketTunnel` extension target on iOS.
- **wstunnel client:** run in-process, listening on `127.0.0.1:<port>`, with WireGuard's endpoint pointed at it.
  - Target build: a small Rust crate `native/wstunnel_ffi` that wraps the `wstunnel` crate (pinned to 10.5.2) and exposes a C API (`start(config)`, `stop()`). It is built with `cargo-ndk` for Android and as an XCFramework for iOS.
  - Android spike shortcut: package the official Android binary as `libwstunnel.so` and run it from `nativeLibraryDir`.
- **Routing loop:** prevented by excluding the server IPs from the tunnel routes. The client connects by IP with SNI/Host set to `vpn.radarcut.com`, so it does not depend on DNS during startup.

## Spike acceptance criteria (Phase 2)

1. An Android physical device connects through wstunnel to a test peer on `wg1`, and the public IP seen is the VPS's.
2. An iOS physical device does the same inside the Packet Tunnel extension, with peak memory below 40 MB.
3. The tunnel survives a switch between Wi-Fi and mobile data and 30 minutes idle.

## Fallback

If the spikes fail, implement the wstunnel client protocol as a custom wireguard-go `conn.Bind` (UDP datagrams over WebSocket) in a forked bridge. That gives one Go runtime and no loopback, but it is custom protocol code that must be tested against server 10.5.2.

## Consequences

- Full control over connection states, routing and the transport.
- The iOS build needs the Go and Rust toolchains plus Network Extension entitlements; CI setup gets heavier.
