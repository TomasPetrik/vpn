# Privacy Policy patch — diagnostics + Settings (2026-11-19)

Publish on https://petrixon.com/vpn/privacy/ (and mirror on the hub privacy glance if needed).
Bump **Last updated** to the publish date.

## Why

Settings now lets users upload **diagnostic reports** (connect log + device/VPN metadata) to `POST /api/v1/devices/me/diagnostics`. Those records are stored under the device in admin. The live policy does not mention this yet. Section 3.4 currently says local stats stay on device “unless described elsewhere,” so diagnostics must be described.

## Add as new §3.7 (after 3.6)

### 3.7 Voluntary diagnostic reports

If you use **Send diagnostic data** in Settings, the app uploads a support report associated with your anonymous device registration. A report may include:

- recent in-app connect / tunnel log lines (the same technical log visible in developer builds);
- app version and build;
- device metadata already described in §3.1 (platform, model, OS, installation ID);
- VPN session state (connected/disconnected, peer server country/name, latency estimate, session byte counters);
- the public IP our API observes for that upload (and approximate country derived from that IP, when available).

We use these reports only to troubleshoot connectivity and support requests. They are **not** browsing history, DNS logs, or VPN packet payloads. Reports are stored on our servers linked to the device record until you request deletion or we purge them as part of ordinary retention.

## Adjust §3.4 last sentence

Replace:

> That local data does not leave the device unless described elsewhere in this policy.

With:

> That local data does not leave the device unless you send it (for example via **Send diagnostic data** in Settings) or as otherwise described in this policy.

## Adjust §3.5 (API operational data)

Add explicitly:

> We may store the public IP used to reach our API (`last_client_ip`) and an approximate country code derived from that IP (`last_client_country`) on the device record for security, abuse prevention, and support.

## Adjust §5 (How we use data)

Add bullet:

> to receive and review voluntary diagnostic reports you submit from Settings for support and troubleshooting;

## Adjust §8 (Retention)

Add bullets aligned with operations:

> - Device and peer records are kept until you request deletion (subject to legal retention needs).
> - Peer traffic sample counters used for capacity charts are retained for up to 365 days.
> - Diagnostic reports you submit are kept with the device record for support; they are deleted or anonymized when the device record is deleted, or earlier if we purge old reports.

Also state: **We aim to respond to deletion requests within 30 days.**

## Apple Guideline 5.4 wording (backlog item)

Prefer an unqualified VPN commitment paragraph (hosting as a separate sentence), e.g.:

> We do not sell user data obtained through the VPN. We do not use VPN traffic content for advertising, analytics products, or other commercial purposes. We do not disclose user data obtained through the VPN to third parties for any purpose. Our VPN servers are operated by us; infrastructure hosting is under our control and instructions.

(Keep the existing “required by law” disclosure in Sharing if counsel wants it, but do not weaken the 5.4 commitment with broad third-party exceptions.)

## Hub page (https://petrixon.com/vpn/)

Under “What we process”, add:

> - Optional diagnostic reports you send from Settings (connect log + device/VPN metadata)

## Terms of Use

No change required for diagnostics. Current Terms already match the free / no-account / no-IAP product. Do not add subscription/billing sections until a paid plan exists.
