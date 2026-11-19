# iOS App Store release checklist (PetrikVPN)

Work top to bottom. Each section is one sitting. Tick a box only when that item is true for the build you will upload.

App identity already in the project:

- Name: PetrikVPN
- Bundle ID: `cz.tomaspetrik.petrikvpn`
- Packet Tunnel extension: `cz.tomaspetrik.petrikvpn.PacketTunnel`
- App Group: `group.cz.tomaspetrik.petrikvpn`
- Team: `56S59F5D36`
- Version in `pubspec.yaml`: `1.0.1+2` (name `1.0.1`, build `2`)
- Minimum iOS: 15.0
- Legal pages: https://petrixon.com/vpn/ · https://petrixon.com/vpn/privacy/ · https://petrixon.com/vpn/terms/
- Product scope for this release: no accounts, no in-app purchases, no ads

Policy detail shared with Android lives in `docs/store_compliance_checklist.md`. This file is the iOS release sequence.

---

## 1. Apple Developer account (blocks everything else)

Guideline 5.4: a VPN app can only be offered by a developer enrolled as an **Organization**. An Individual account cannot ship this app.

- [ ] Confirm the account for team `56S59F5D36` is an Organization enrollment, not Individual.
- [ ] If it is Individual, convert or re-enroll (legal entity + D-U-N-S) before any other App Store work.
- [ ] Agreements, tax, and banking in App Store Connect are Active (Paid Apps agreement is required even for a free app).

## 2. App IDs and capabilities

Local entitlements already request Packet Tunnel, the App Group, and keychain access. The Developer portal must match, for **both** the app and the extension.

- [ ] App ID `cz.tomaspetrik.petrikvpn` exists, with Network Extensions (Packet Tunnel) and App Groups (`group.cz.tomaspetrik.petrikvpn`).
- [ ] App ID `cz.tomaspetrik.petrikvpn.PacketTunnel` exists, with the same Network Extensions and App Group.
- [ ] An App Store distribution certificate and App Store profiles exist for both IDs (Xcode automatic signing can create these on archive).

## 3. Product decisions before UI work

- [ ] Ship iPhone only for v1, **or** keep iPad. The Xcode target is currently universal (`TARGETED_DEVICE_FAMILY = 1,2`). iPhone-only avoids iPad screenshots and iPad layout review. If iPad stays, the UI must be usable on iPad.
- [ ] Keep this release free, with no login and no “PRO” or paid-tier copy. The unused Account screen still says “PetrikVPN PRO” and “Vault settings will land here.” Do not ship that screen.
- [ ] Decide storefronts. Offer the app only where this company may legally offer a consumer VPN. Do not write the listing as a tool for bypassing the law.

## 4. In-app compliance (Guideline 5.4)

Apple requires a plain-language screen, shown before the first connect, that says what is collected and how it is used. The privacy policy must also say the VPN data is not sold or disclosed to third parties for any purpose.

- [x] Disclosure screen before the first Connect: device registration data, device/app metadata, WireGuard public key, technical peer stats; used to provide the VPN, security, force-upgrade, and abuse prevention; browsing content is not sold and not given to third parties for advertising; link to the privacy policy; an explicit Continue before the tunnel starts.
- [x] Settings (or equivalent) links, easy to find:
  - Privacy Policy → `https://petrixon.com/vpn/privacy/`
  - Terms of Use → `https://petrixon.com/vpn/terms/`
- [x] “Request data deletion” pointing at `info@petrixon.com`, telling the user what to include (platform, device model, any installation id the app shows). Do not invent an account just to satisfy account-deletion rules.
- [ ] Purpose of the VPN permission matches the product: VPN connectivity only.
- [ ] Release build has `DEV_MODE` off (that is already the default). Confirm the debug API log is not reachable in the uploaded build.

## 5. Release build hygiene

- [ ] `pubspec.yaml` version is the one you want on the store. Build number (`+N`) must go up for every upload.
- [ ] App and Packet Tunnel show the same version name and build. Today the app follows Flutter (`1.0.1` / build from pubspec) and the extension has `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` hardcoded (`1.0.1` / `2`). Align them before archive.
- [ ] Replace the temporary App Store URL in `lib/features/app_update/domain/app_store_links.dart`. It currently opens a different app. Until the real listing exists, point force-upgrade at a page you control, not at another product.
- [ ] Production API stays `https://vpn.radarcut.com` (the default). A fresh device with no account must be able to register and connect during review. A device cap or a force-upgrade floor above this build will fail review.
- [ ] Admin force-upgrade: `min_supported_build` is at or below this build for the whole review period.
- [ ] App icon: 1024×1024, no alpha, no pre-rounded corners. Icon generation is already set up (`remove_alpha_ios: true`).
- [ ] Add `ITSAppUsesNonExemptEncryption` = false to `ios/Runner/Info.plist` if the only cryptography is standard HTTPS and WireGuard (the usual exemption). Confirm that reading before relying on it. This stops App Store Connect from asking the encryption question on every upload.
- [ ] Archive a release build and open the privacy report. There is no `PrivacyInfo.xcprivacy` in this repo. Fix any missing required-reason API entries before upload (ITMS-91061).

## 6. App Store Connect record

- [ ] Create the app with bundle ID `cz.tomaspetrik.petrikvpn`, name PetrikVPN, primary language, and SKU.
- [ ] Category: Utilities (secondary optional).
- [ ] Price: Free. No in-app purchases.
- [ ] Privacy Policy URL: `https://petrixon.com/vpn/privacy/`
- [ ] Support URL: `https://petrixon.com/vpn/`
- [ ] Age rating questionnaire. Expect 4+ if the answers match a VPN with no restricted content.
- [ ] App Privacy labels, matching the table in `docs/store_compliance_checklist.md` section E. Not used for tracking. Not sold. No name, email, payment, precise location, contacts, or photos.
- [ ] Availability limited to the storefronts chosen in section 3.
- [ ] Description, subtitle, and keywords describe a personal VPN. State that there is no account. Do not claim “no logs” more broadly than the privacy policy (no browsing, DNS, or content logs). No “military-grade” or “100% anonymous.”
- [ ] Screenshots for every size App Store Connect marks required. If iPhone-only: the current 6.9-inch iPhone slot. If iPad stays: the 13-inch iPad slot as well. Use the real app, including the disclosure screen.
- [ ] Review notes: no login; open the app; accept the disclosure; tap Connect; accept the system VPN permission; the server is the production endpoint (Germany). Mention the Network Extension and that there is no account and no purchase.
- [ ] Export compliance answered consistently with the Info.plist flag in section 5.
- [ ] Content rights / third-party content: this app does not ship third-party media that needs rights.

## 7. TestFlight, then submit

- [ ] `flutter build ipa` (release, no `DEV_MODE=true`) archives and uploads.
- [ ] Build appears in TestFlight and finishes processing.
- [ ] Install from TestFlight on a clean iPhone: disclosure, Connect, system VPN permission, handshake, traffic, disconnect, force-quit, reopen.
- [ ] Privacy, Terms, and deletion links open the live pages.
- [ ] Update-required screen, if shown, does not send the user to the placeholder app.
- [ ] Submit the tested build for review.
- [ ] Leave the VPN server up until the review finishes.
- [ ] After approval, replace any temporary update URL with the real App Store link (`https://apps.apple.com/app/id…`).

## 8. After the first approval

- [ ] Written deletion runbook for mail to `info@petrixon.com` (find the device record, delete or anonymize it, reply inside the SLA you publish).
- [ ] Production logs still contain no traffic, DNS, or content logs.
- [ ] Each later upload uses a higher build number and the same compliance answers.
