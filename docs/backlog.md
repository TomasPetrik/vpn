# PetrikVPN backlog (post iOS Step 5)

Last updated: 2026-11-17

## Done (iOS path)

- PacketTunnel + WireGuardKit
- wstunnel 10.5.2 FFI in extension (WSS by IP + SNI)
- Peer apply on `wg1` via netlink
- Handshake + real traffic through VPS (DE)

## Open

1. ~~**TLS verify on iOS**~~ — webpki-roots in vendored wstunnel; `tls_verify_certificate: true` (device verify: prod connect OK + bad SNI fails).
2. ~~**PacketTunnel memory**~~ — ~8 MB peak after 500 MB download (Profile); well under ~50 MB jetsam.
3. ~~**Android**~~ — VpnService + GoBackend + wstunnel_ffi (cargo-ndk); Flutter `vpn_engine` unlocked (device E2E verify).
4. ~~**Stability tests**~~ — sleep 6h, Wi‑Fi gap 15m, airplane, force-quit; cellular handoff still open when roaming OK.
5. ~~**Admin traffic counters**~~ — fixed: vpn-api syncs `wg` peer RX/TX + handshake into MySQL every 15s and on device detail load.
6. ~~**Connect UI handshake / RX/TX**~~ — session stats on Home (1s poll) + overall Statistics screen.

## Nice-to-have

- ~~Soft update banner CTA~~ — Update + dismiss; temp App Store link until PetrikVPN listing exists
- Sim slice for WstunnelFFI XCFramework (device-only today)
- Replace temp App Store URL with real PetrikVPN listing
