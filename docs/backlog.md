# PetrikVPN backlog (post iOS Step 5)

Last updated: 2026-11-17

## Done (iOS path)

- PacketTunnel + WireGuardKit
- wstunnel 10.5.2 FFI in extension (WSS by IP + SNI)
- Peer apply on `wg1` via netlink
- Handshake + real traffic through VPS (DE)

## Open

1. ~~**TLS verify on iOS**~~ — webpki-roots in vendored wstunnel; `tls_verify_certificate: true` (device verify: prod connect OK + bad SNI fails).
2. **PacketTunnel memory** — formal measurement under load vs ~50 MB jetsam budget (Instruments / on-device).
3. **Android** — VpnService + wireguard-go + wstunnel client (binary or FFI); end-to-end same as iOS.
4. **Stability tests** — Wi‑Fi ↔ cellular handoff, 30+ min idle, reconnect after sleep; document results.
5. ~~**Admin traffic counters**~~ — fixed: vpn-api syncs `wg` peer RX/TX + handshake into MySQL every 15s and on device detail load.

## Nice-to-have

- Surface last handshake / transfer in the app Connect UI
- Sim slice for WstunnelFFI XCFramework (device-only today)
