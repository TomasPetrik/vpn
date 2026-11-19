# Store compliance checklist (PetrikVPN)

Target release: **no end-user accounts**, **no in-app purchases / subscriptions**.

Public legal URLs:

- Hub: https://petrixon.com/vpn/
- Privacy Policy: https://petrixon.com/vpn/privacy/
- Terms of Use: https://petrixon.com/vpn/terms/

Privacy contact: `info@petrixon.com`

---

## A. Must implement in the app (before submit)

### A1. In-app Privacy Policy + Terms links
- [x] Add easily reachable links (Settings / About / overflow menu is fine) to:
  - Privacy Policy → `https://petrixon.com/vpn/privacy/`
  - Terms of Use → `https://petrixon.com/vpn/terms/`
- [x] Apple requires the privacy policy link in the app, not only in App Store Connect.
- [x] Google requires a privacy policy link or text inside the app.

### A2. Pre-VPN data disclosure screen (Apple 5.4 + Google VpnService)
Show **before the first Connect** (not buried in Settings), in plain language:

- [x] What data is collected (anonymous device registration, device/app metadata, WireGuard public key, technical peer stats).
- [x] That VPN traffic content / browsing history is **not** sold and **not** disclosed to third parties for advertising.
- [x] How data is used (provide VPN, security, force-upgrade, abuse prevention).
- [x] Link to the full Privacy Policy.
- [x] Affirmative consent (e.g. Continue / I understand) **before** first tunnel use.
- [x] Google: this VpnService disclosure must be **separate** from other permission dialogs and not only in the privacy policy.

### A3. System VPN permission UX
- [ ] iOS: use Network Extension / Packet Tunnel (already planned); show system VPN permission promptly and honestly.
- [ ] Android: use `VpnService` and the system VPN consent dialog; do not bypass it.
- [ ] Purpose strings / copy must match reality (VPN connectivity only).

### A4. Data deletion path (even without accounts)
- [x] In-app: short “Request data deletion” text pointing to `info@petrixon.com`, or an in-app mail compose.
- [x] Document what the user should include (platform, device model, any shown device/installation id).
- [x] Operator process: locate device record and delete/anonymize user+device+peer (+ diagnostic reports) within a defined SLA (e.g. 30 days). See `docs/legal/deletion_runbook.md`.

### A5. Keep product scope matching “free / no account / no IAP”
- [ ] Do not add login walls.
- [ ] Do not add IAP, subscriptions, or paid unlocks in this release.
- [ ] Do not add advertising / tracking SDKs without updating privacy policy + store forms first.

---

## B. Apple App Store

### B1. Organization enrollment (blocking for VPN)
- [ ] Confirm Apple Developer Program enrollment type is **Organization**, not Individual.
- [ ] Apple Guideline **5.4**: VPN apps may only be offered by organization-enrolled developers.
- [ ] If currently Individual: convert / re-enroll as Organization (D-U-N-S, legal entity) before VPN submission.

### B2. App Store Connect metadata
- [ ] Privacy Policy URL: `https://petrixon.com/vpn/privacy/`
- [ ] (Optional) Privacy Choices / deletion info URL can also point to the privacy page deletion section.
- [ ] Complete **App Privacy** nutrition labels to match the policy (device ID, product interaction / diagnostics as applicable; **not used for tracking**; **not sold**).
- [ ] Age rating questionnaire answered accurately.
- [ ] Support URL (can be `https://petrixon.com/vpn/` or a mailto support page).
- [ ] Review notes: explain no accounts, no IAP, anonymous device token, Network Extension usage.

### B3. VPN / Network Extension review expectations
- [ ] App uses supported Network Extension VPN APIs (Packet Tunnel), not private APIs.
- [ ] Privacy policy contains the **no sell / no disclose to third parties for any purpose** VPN commitment (already on the public page).
- [ ] If distributing in a country that requires a VPN license, put license info in Review Notes (or do not ship there).

### B4. Account deletion rule
- [ ] N/A for true no-account apps. Do **not** invent a fake “account” UX that would trigger Apple’s account-deletion requirement without implementing deletion in-app.
- [ ] Still offer deletion of device registration data on request (A4).

### B5. Export compliance / encryption
- [ ] Answer export compliance / encryption questions for HTTPS + WireGuard correctly (usually standard encryption exemptions documentation).

---

## C. Google Play

### C1. Play Console declarations
- [ ] Privacy Policy URL: `https://petrixon.com/vpn/privacy/`
- [ ] Complete **Data safety** form consistently with the privacy policy and actual SDK behavior.
- [ ] Declare collected data types (e.g. Device or other IDs, App info and performance) and purposes (App functionality, Account management equivalent, Fraud prevention/security).
- [ ] Declare data is encrypted in transit; not sold; not used for advertising.
- [ ] Submit **VpnService declaration** (VPN as core functionality).
- [ ] Document VPN use in the Play Store listing description (core purpose = VPN).

### C2. Listing / policy text
- [ ] Store description states the app provides a VPN using Android `VpnService`.
- [ ] Do not claim “no logs” more broadly than the privacy policy (be precise: no browsing/DNS/content logs).
- [ ] No misleading “military-grade / 100% anonymous” claims.

### C3. Permissions
- [ ] Only request permissions needed for VPN core functionality.
- [ ] If any sensitive permissions are declared, justify them in the declaration forms.

### C4. Billing
- [ ] Leave Play Billing / subscriptions unused for this release.
- [ ] If you later add paid plans, revisit IAP rules and update Terms + Data safety.

---

## D. Operator / backend compliance ops

- [ ] Confirm production logging still matches the privacy policy (no traffic/DNS/content logs).
- [ ] Keep admin access restricted; do not export device lists for marketing.
- [x] Have a written deletion runbook for `info@petrixon.com` requests (`docs/legal/deletion_runbook.md`).
- [ ] Abuse process: how you block a device and when you retain minimal evidence.
- [ ] Hosting / VPS terms: confirm VPN egress is allowed on the provider contract.
- [ ] If user base grows beyond private/friends: revisit jurisdiction, logging, and abuse tooling.

---

## E. Suggested App Privacy / Data safety mapping (current architecture)

Collected / processed:

| Data | Purpose | Notes |
| --- | --- | --- |
| Installation ID + hashed optional device id + device token hash | App functionality / fraud prevention | Anonymous device registration |
| Manufacturer, model, OS, app version/build | App functionality | Force-upgrade + support |
| WireGuard public key, tunnel IP, peer byte/handshake stats | App functionality | VPN provisioning/ops |
| API source IP (proxy/rate limit) + approximate country | Security | Stored on device record (`last_client_ip` / `last_client_country`) |
| Voluntary diagnostic reports (connect log + metadata) | App functionality / support | Only when user taps Send diagnostic data |

Not collected: name, email, payment info, precise location, contacts, photos, ads interactions, tracking across apps.

**Policy sync:** publish `docs/legal/privacy_policy.md` (and hub glance patch) to petrixon.com before store submit. Live site is on Websupport, not this repo.

---

## F. Release order (practical)

1. Publish legal pages (done when live on petrixon.com/vpn).
2. Implement A1–A4 in the Flutter app.
3. Fix Apple Organization enrollment if needed (B1).
4. Fill App Privacy + Play Data safety + VpnService declaration.
5. Internal test builds → closed testing → production.
6. Keep policy URLs stable; update page text when practices change.
