# Privacy Policy

**Effective date:** 19 November 2026  
**Last updated:** 19 November 2026  
**Service:** PetrikVPN mobile application (iOS and Android)  
**Operator:** Petrixon (“we”, “us”, “our”)  
**Privacy contact:** info@petrixon.com

> **VPN privacy commitment (Apple App Store Guideline 5.4).** We do not sell user data obtained through the VPN. We do not use VPN traffic content for advertising, analytics products, or other commercial purposes. We do not disclose user data obtained through the VPN to third parties for any purpose. Our VPN servers are operated by us in Germany; infrastructure hosting is under our control and instructions.

## 1. Who we are

PetrikVPN is operated by Petrixon. For privacy questions, data-access requests, or deletion requests, email **info@petrixon.com**.

The VPN backend is operated by us on infrastructure we control (currently a server in Germany).

## 2. Scope and no accounts / no purchases

This Privacy Policy applies to the PetrikVPN mobile apps and the related VPN API and tunnel service. The current release:

- does not require a user account, email, or password;
- does not offer in-app purchases, subscriptions, or payments;
- does not include advertising SDKs or third-party marketing analytics SDKs.

On first launch the app silently creates an anonymous device registration so we can provision a VPN configuration for that installation. That is not an end-user login account.

## 3. What we collect

We collect only what is needed to run and secure the VPN service.

### 3.1 Device and app information (sent to our API)

- **Installation ID** — a random UUID created by the app and stored on the device.
- **Optional device identifier** — when available from the OS/device APIs; on our servers we store only an HMAC hash of it, never the raw value.
- **Platform** — Android or iOS.
- **Device metadata** — manufacturer, model, OS version, and whether the device reports as physical.
- **App version metadata** — app version string and build number (used for force-upgrade / compatibility).
- **Timestamps** — registration time and last-seen time for the device record.

### 3.2 Authentication token

After registration we issue an opaque device token. The app stores it in the platform secure storage and sends it as a bearer token to our API. We store only a SHA-256 hash of the token on the server.

### 3.3 VPN technical configuration

- WireGuard public key generated on the device;
- assigned tunnel IPv4 address;
- optional peer statistics we maintain for operations (last handshake time, approximate bytes transferred, and time-bucketed transfer samples used for capacity charts).

### 3.4 Data stored only on your device

The app may keep local connection statistics and preferences on the device (for example session transfer counters shown in the UI). That local data does not leave the device unless you send it (for example via **Send diagnostic data** in Settings) or as otherwise described in this policy.

### 3.5 Limited server / API operational data

Our reverse proxy and API may process standard technical request metadata needed for security and reliability (for example IP address used to reach the API, approximate time, and rate-limiting signals). We may store the public IP used to reach our API (`last_client_ip`) and an approximate country code derived from that IP (`last_client_country`) on the device record for security, abuse prevention, and support. We do not use this to build advertising profiles.

### 3.6 What we do not collect

- Name, email, phone number, postal address, or payment details;
- precise GPS location for the VPN product;
- address books, photos, microphone, camera, or health data;
- browsing history, DNS query logs, or packet payloads of VPN-tunneled traffic (see below).

### 3.7 Voluntary diagnostic reports

If you use **Send diagnostic data** in Settings, the app uploads a support report associated with your anonymous device registration. A report may include:

- recent in-app connect / tunnel log lines (the same technical log visible in developer builds);
- app version and build;
- device metadata already described in §3.1 (platform, model, OS, installation ID);
- VPN session state (connected/disconnected, peer server country/name, latency estimate, session byte counters);
- the public IP our API observes for that upload (and approximate country derived from that IP, when available).

We use these reports only to troubleshoot connectivity and support requests. They are **not** browsing history, DNS logs, or VPN packet payloads. Reports are stored on our servers linked to the device record until you request deletion or we purge them as part of ordinary retention.

## 4. VPN traffic and what we do not log

When the VPN is connected, your device’s IP traffic is encrypted from the device to our VPN server (WireGuard over a WebSocket/TLS transport) and then forwarded to the public internet.

For VPN-tunneled traffic we do not intentionally keep:

- destination website or IP browsing history logs;
- DNS query logs of tunneled traffic;
- packet payloads / content of your communications.

Aggregated or ephemeral peer counters (handshake / byte totals) may exist for capacity and abuse handling. They are not sold and are not used for advertising.

## 5. How we use data

- to register the installation and issue a device token;
- to provision and update WireGuard peer configuration;
- to operate, secure, and troubleshoot the VPN service;
- to enforce app minimum-version / force-upgrade policies;
- to prevent abuse (for example blocking a device that violates the Terms);
- to receive and review voluntary diagnostic reports you submit from Settings for support and troubleshooting;
- to respond to your privacy requests and legal obligations.

We do not use the data for advertising, sale of personal data, or cross-app tracking.

## 6. Legal bases (EEA / UK / Switzerland)

Where GDPR (or UK GDPR) applies, we process data based on:

- **Contract / requested service** — providing the VPN you ask the app to connect;
- **Legitimate interests** — securing the service, preventing abuse, keeping the app compatible;
- **Legal obligation** — when we must respond to a binding legal request.

## 7. Sharing and processors

We do not sell personal data. We do not share VPN traffic content with third parties for advertising or analytics. We may use infrastructure providers that host servers or deliver connectivity strictly as processors/subprocessors under our instructions (for example a VPS hosting provider). Those providers should not use your data for their own marketing.

We may disclose information if required by applicable law, regulation, legal process, or governmental request, or to protect the rights, safety, and integrity of the service.

Apple App Store and Google Play are independent platforms. Their processing of developer account, review, and distribution data is governed by Apple’s and Google’s own policies.

## 8. Retention

- Device and peer records are kept until you request deletion (subject to legal retention needs).
- Peer traffic sample counters used for capacity charts are retained for up to **365 days**.
- Diagnostic reports you submit are kept with the device record for support; they are deleted or anonymized when the device record is deleted, or earlier if we purge old reports.
- Local on-device data is removed when you uninstall the app (platform behavior applies).

We aim to respond to deletion requests within **30 days**.

## 9. Your rights and deletion

Depending on where you live, you may have rights to access, correct, delete, restrict, or object to certain processing, and to lodge a complaint with a supervisory authority (for example the Slovak Data Protection Office / your local EU authority).

Because there is no account login, deletion is handled by email or via **Request data deletion** in Settings (which opens a pre-filled message). Send a request to **info@petrixon.com** from a contact address you control and include:

- that the request concerns PetrikVPN data deletion;
- platform (iOS or Android);
- any device / installation identifiers you can find in the app (if shown), or approximate registration timing and device model to help us locate the record.

We may ask for limited additional information to verify that we are deleting the correct device record. We will not require you to create an account solely to exercise deletion rights.

## 10. Security

- VPN tunnel traffic is encrypted between the app and our VPN endpoint.
- Device tokens and WireGuard keys are handled as secrets; tokens are stored hashed at rest on the server.
- Raw optional device identifiers are not stored; only an HMAC is kept.
- No method of transmission or storage is 100% secure; use the service accordingly.

## 11. Children

PetrikVPN is not directed at children under 13 (or the higher age required in your country, such as 16 where applicable). We do not knowingly collect personal data from children. If you believe a child has used the service, contact us and we will delete related records.

## 12. International transfers

Our VPN server is currently located in Germany (EU). If you connect from outside the EU, your traffic and the limited device metadata described above are processed in the EU to provide the service.

## 13. App Store and Google Play disclosures

Apple App Privacy labels and Google Play Data safety answers are summaries that must match this policy. In short, for the current free build we expect to declare collection of device identifiers / app info / diagnostics-style technical data used for app functionality and account management equivalents (anonymous device registration), not for tracking, and not sold. Update those store forms whenever this policy or the app’s data practices change.

## 14. Changes

We may update this Privacy Policy. The “Last updated” date above will change when we do. Material changes may also be communicated in the app or on petrixon.com/vpn.

## 15. Contact

Privacy questions and deletion requests:  
Email: **info@petrixon.com**  
Web: https://petrixon.com/vpn/
