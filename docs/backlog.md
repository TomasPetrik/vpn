# PetrikVPN backlog (post iOS Step 5)

Last updated: 2026-11-19

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
7. **Privacy leftovers (before App Store submit)**
   - App: bundle Inter and JetBrains Mono so `google_fonts` does not fetch from Google at runtime.
   - ~~Drop `api.country.is` / `api.ipify.org`~~ — country/IP from our API only.
   - ~~In-app Privacy/Terms + deletion + pre-Connect disclosure~~ — Settings + connect sheet.
   - **Publish** `docs/legal/privacy_policy.md` (+ hub glance patch) on petrixon.com (Websupport). Until then the live policy is behind the app.
   - App Store Connect, after the policy is live: App Privacy declares only device / technical data (+ diagnostics when user-initiated), not used for tracking, not sold, no third-party partners. Privacy Policy URL stays `https://petrixon.com/vpn/privacy/`.
8. **Terms of Use leftovers (before App Store submit)**
   - Terms on petrixon.com already match the free app (acceptable use, VPN limits, no account, liability, Slovak law). **No Terms change needed for Settings/diagnostics.** Do not add subscription, billing, renewal, cancellation, or refund sections until there is a paid plan.
   - EULA choice: leave the App Store Connect EULA field empty so Apple’s standard EULA applies, or attach `https://petrixon.com/vpn/terms/` and add the Schedule 2 clauses to section 9: support and warranties sit with Petrixon; Apple refunds the purchase price if a warranty fails; Petrixon handles intellectual-property claims; Apple is a third-party beneficiary and can enforce the terms.
   - Auto-renewable subscriptions only: functional in-app links to both the privacy policy and the Terms of Use, plus the same terms link in the App Store description or EULA field. Not required for this release.

## Nice-to-have

- ~~Soft update banner CTA~~ — Update + dismiss; temp App Store link until PetrikVPN listing exists
- Sim slice for WstunnelFFI XCFramework (device-only today)
- Replace temp App Store URL with real PetrikVPN listing
