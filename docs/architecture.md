# System architecture

Status: **Approved on 2026-11-16 (Phase 1).** Implementation starts in Phase 2 ([plan](phase2_plan.md)). So far only DNS (C1) and the wstunnel hardening (C6) are applied on the server.

Related documents: [Flutter](flutter_architecture.md) · [Backend](backend_architecture.md) · [Database](database.md) · [API](api.md) · [Existing VPS](vps_existing_infrastructure.md) · [Decisions](decisions/README.md)

## 1. Scope of v1

**Product:** **PetrikVPN** (`cz.tomaspetrik.petrikvpn`), a general-purpose VPN with one server in Germany, for family and friends at first (10–20 active users).

**In scope:** first launch, automatic device registration and user creation, VPN connect and disconnect, basic connection status, basic server information, **force upgrade controlled from the admin panel**, and a minimal admin panel (login, users, devices, peer status, server status, app update policy).

**Out of scope:** subscriptions, payments, lifetime or access codes, end-user accounts, multiple servers, marketing and analytics.

## 2. Overview

```mermaid
flowchart LR
  subgraph phone["Phone: iOS / Android"]
    ui["Flutter UI, BLoC"]
    engine["Native VPN engine: WireGuard + wstunnel client"]
  end
  subgraph vps["VPS 72.61.158.103"]
    apache["Apache :443, vhost vpn.radarcut.com (new)"]
    api["vpn-api, Go, 127.0.0.1:8090 (new)"]
    db[("MySQL 8.0, db vpn (new)")]
    wst["wstunnel :8080 (existing, owner only)"]
    wstapp["wstunnel-app 127.0.0.1:8081 (new, app only)"]
    wg1["wg1 10.201.0.0/16 UDP 51821 (new)"]
    wg0["wg0 10.200.200.0/24 UDP 51820 (existing)"]
    nat["NAT on eth0"]
  end
  mac["MacBook (existing)"]
  ui -- "HTTPS /api/v1" --> apache
  apache --> api
  api --> db
  api -- "wgctrl / netlink" --> wg1
  engine -- "wss /prefix" --> apache
  apache -- "ws" --> wstapp
  wstapp -- "UDP 127.0.0.1:51821" --> wg1
  mac -- "ws :8080" --> wst
  wst -- "UDP 127.0.0.1:51820" --> wg0
  wg1 --> nat
  wg0 --> nat
  nat --> internet((Internet))
```

| Component | Location | New or existing |
| --- | --- | --- |
| Flutter app | iOS, Android | new |
| Native VPN engine (wireguard-go + embedded wstunnel client) | Android `VpnService`, iOS Packet Tunnel extension | new |
| Apache vhost `vpn.radarcut.com` (TLS, reverse proxy) | VPS :443 | Apache existing, vhost new |
| `vpn-api`: REST API, admin panel, peer provisioning | VPS `127.0.0.1:8090`, systemd | new |
| MySQL database `vpn` | VPS localhost (MySQL 8.0.46) | server existing, database new |
| wstunnel 10.5.2, service `wstunnel` (owner's MacBook) | VPS :8080, restricted to `wg0` | existing, untouched |
| wstunnel 10.5.2, service `wstunnel-app` (mobile app) | VPS `127.0.0.1:8081` behind Apache, restricted to `wg1` | new instance of the installed binary |
| WireGuard `wg1` for app clients | VPS, UDP 51821 reachable only from localhost | new |
| WireGuard `wg0` for the owner's MacBook | VPS, UDP 51820 | existing, untouched |

## 3. Mobile data path

```text
apps -> tun (wireguard-go) -> UDP 127.0.0.1:<local port>
  -> embedded wstunnel client -> wss://vpn.radarcut.com/<prefix> (TLS 443, Apache)
  -> ws://127.0.0.1:8081 (wstunnel-app, separate instance for the app)
  -> UDP 127.0.0.1:51821 -> wg1 -> NAT on eth0 -> internet
```

The VPS public IP is excluded from the tunnel routes, so the wstunnel connection and API calls never loop back into the tunnel. IPv6 is routed into the tunnel and dropped there, which prevents IPv6 leaks, because the server has no IPv6 forwarding.

## 4. Main flows

### 4.1 First launch and registration

```mermaid
sequenceDiagram
  participant App as Flutter app
  participant API as vpn-api
  participant DB as MySQL
  App->>App: load or create installation_id, read device identifier and device info
  App->>API: POST /api/v1/devices/register
  API->>DB: find device by token, identifier hash, installation_id
  alt known device
    API->>DB: update device info, rotate token if no valid token was sent
  else new device
    API->>DB: insert user and device in one transaction
  end
  API-->>App: user_id, device_id, device_token
  App->>App: store token in secure storage, ids in Drift
```

Registration runs silently on first launch. If it fails (for example offline), the home screen still opens and registration is retried on the first connect.

### 4.2 Connect

```mermaid
sequenceDiagram
  participant B as VpnBloc
  participant N as Native engine
  participant API as vpn-api
  participant WG as wg1
  B->>N: getPublicKey() (key pair created natively on first use)
  B->>API: PUT /api/v1/devices/me/peer {public_key}
  API->>API: allocate tunnel IP, save peer in DB
  API->>WG: add or update peer via wgctrl
  API-->>B: VPN config
  B->>N: prepare() (OS VPN permission)
  B->>N: connect(config)
  N->>N: start wstunnel client, then WireGuard
  N-->>B: connecting, then connected after first handshake
```

The last config is cached. If the API is unreachable, the app connects with the cached config and refreshes it later. If the handshake does not complete, the app re-provisions once.

### 4.3 Disconnect

The native engine stops WireGuard and then the wstunnel client. The peer stays provisioned on the server, so reconnecting needs no API call.

### 4.4 Admin

A browser opens `https://vpn.radarcut.com/admin`, which Apache proxies to `vpn-api` (server-rendered HTML). Users and devices come from the database; peer status comes live from `wg1` through `wgctrl`, with counters cached in the database.

### 4.5 Force upgrade

```mermaid
sequenceDiagram
  participant Admin
  participant API as vpn-api
  participant App as Flutter app
  Admin->>API: /admin/app-versions: set minimum build (confirm "N devices will be blocked")
  App->>API: GET /api/v1/app/config?platform&build (start, resume)
  API-->>App: update.status = required, update_url, message
  App->>App: disconnect VPN, show blocking page with update button
  App->>API: any other call from an old build
  API-->>App: 426 app_update_required
```

The policy is set per platform. A soft "update available" prompt is also possible ([ADR-0007](decisions/0007-force-upgrade.md)). The mechanism ships in the very first build.

## 5. Security model (summary)

- The mobile device identifier is a **recognition signal only**. Authentication uses a random per-device token issued by the backend and stored hashed ([ADR-0004](decisions/0004-device-recognition-and-authentication.md)).
- WireGuard private keys are generated on the device and never leave it ([ADR-0003](decisions/0003-client-generated-wireguard-keys.md)).
- `wg1` is isolated: no client-to-client traffic, no access to `wg0` or to VPS services, and outbound SMTP is blocked.
- Admin: argon2id passwords, secure session cookie, CSRF tokens, login rate limiting. Admins are created only through the CLI.
- Secrets live in `/etc/vpn-api/env` on the VPS, never in the repository, logs or docs.
- Data minimisation: no traffic, DNS or connection logs. The backend stores only each peer's last handshake and byte counters.

## 6. Repository layout

```text
ru_eu_vpn/
├── lib/ android/ ios/ test/   Flutter app (stays at the repo root)
├── backend/                   Go module: API, admin, deploy files
├── native/wstunnel_ffi/       Rust wrapper around the wstunnel client (after the spike)
└── docs/
```

## 7. Decisions

| ADR | Decision |
| --- | --- |
| [0001](decisions/0001-reuse-wstunnel-transport.md) | wstunnel as the mobile transport, in a separate instance `wstunnel-app` behind Apache (`wss://` on 443); the owner's instance stays untouched (Accepted) |
| [0002](decisions/0002-dedicated-wg1-interface.md) | A dedicated `wg1` interface for app clients; `wg0` stays untouched |
| [0003](decisions/0003-client-generated-wireguard-keys.md) | WireGuard keys are generated on the device |
| [0004](decisions/0004-device-recognition-and-authentication.md) | Device identifier for recognition, backend token for authentication |
| [0005](decisions/0005-backend-hosting-and-admin.md) | One Go binary behind the existing Apache, the existing MySQL, a server-rendered admin |
| [0006](decisions/0006-native-vpn-engine.md) | In-app native VPN engine: wireguard-go libraries plus an embedded wstunnel client |
| [0007](decisions/0007-force-upgrade.md) | Force upgrade by minimum build per platform, set in the admin panel, enforced by the app and the API |

## 8. Technical risks

| # | Risk | Impact | Mitigation |
| --- | --- | --- | --- |
| R1 | **No ready-made mobile wstunnel library.** It must be embedded through Rust FFI (or by running the Android binary). The iOS Packet Tunnel memory limit is about 50 MB. | High | Spike first on both platforms. Fallback: implement the wstunnel client protocol as a wireguard-go `Bind` ([ADR-0006](decisions/0006-native-vpn-engine.md)). |
| R2 | ~~The existing wstunnel is an open relay into the VPS (finding F1).~~ | Fixed 2026-11-16 | Change C6 applied: only UDP to `127.0.0.1:51820` is allowed. |
| R3 | App store distribution: Apple requires VPN apps on the App Store to be published by an organization account; team `56S59F5D36` is individual for now. | Medium | v1 goes to family and friends through test channels (section 9); App Store release after organization enrollment if required. |
| R4 | DPI and blocking: `ws://` is easy to detect; the Rust TLS fingerprint differs from browsers; blocking one domain or IP takes down both the API and the tunnel. | High | Use `wss` on 443 with a real certificate and a secret path. Later, separate domains or IPs and an alternative transport. |
| R5 | Shared VPS: VPN egress, abuse reports and blocklisting affect `radarcut.com`. The Hostinger terms for VPN/proxy use are unverified. | Low for 10–20 known users; **accepted by the owner for v1** | Block SMTP, isolate `wg1`; a dedicated VPN VPS or IP if the user base grows. |
| R6 | WireGuard over WebSocket/TCP: TCP-over-TCP slowdowns on lossy mobile networks; MTU issues. | Medium | MTU 1280, WebSocket ping, measure. |
| R7 | DNS chicken-and-egg: the wstunnel client must reach `vpn.radarcut.com` while the tunnel's DNS is not up yet. | Medium | Resolve the server IP before the tunnel starts, connect by IP with SNI/Host set to the domain, and exclude that IP from routes. |
| R8 | `mobile_device_identifier` 0.1.0 is from an unverified publisher; MediaDrm-based IDs behave differently across Android vendors and can be missing. | Medium | Treat the identifier as optional; the installation ID is the fallback. |
| R9 | Anyone who knows a device identifier can re-register as that device and rotate its token. | Low in v1 (free, no personal data) | Before payments: App Attest / Play Integrity or account login. |
| R10 | Runtime `wg1` peers are lost when `wg1` restarts. | Low | The database is the source of truth; a reconciler re-applies peers on start and every 60 s. |
| R11 | Capacity: 2 vCPU, 7.8 GiB RAM, no bandwidth limit for now. 10–20 active users is a small load. | Low | Basic throughput test in Phase 3; resource limits on `wstunnel-app`. |
| R12 | Android background limits and OEM battery killers stop the VPN. | Medium | Foreground service, always-on VPN guidance. |
| R13 | Apache WebSocket proxying of long-lived connections (timeouts). | Low | Proxy timeout settings plus 30 s WebSocket pings; test. |
| R14 | The VPN lives on a subdomain of the production site. A host name starting with `vpn.` is visible in TLS SNI and is an easy blocking target. A block of `vpn.radarcut.com` could escalate to all of `radarcut.com`, and the reverse is also true. | Medium; **accepted by the owner for v1** | The tunnel URL is a backend config value delivered by the API (`transport.url`), so it can move to a neutral host name without an app release. Admin and API can stay on `vpn.radarcut.com`. |

## 9. Owner decisions (2026-11-16)

| Topic | Decision |
| --- | --- |
| DNS | `vpn.radarcut.com` created (C1) |
| wstunnel hardening | Done (C6) |
| Shared IP and domain with `radarcut.com` | Accepted for v1 |
| Positioning | A general-purpose VPN, no country-specific targeting. The anti-blocking transport (wstunnel over 443) is a general feature for restrictive networks. |
| Server | One VPS in Germany (`DE`), no bandwidth limit for now |
| Users | Family and friends, about 10–20 active users |
| App name and IDs | **PetrikVPN**, `cz.tomaspetrik.petrikvpn` on both platforms (details in [flutter_architecture.md](flutter_architecture.md)) |
| Apple | Team `56S59F5D36` (Tomas Petrik): individual paid membership for development and Ad Hoc; organization enrollment later if needed for App Store VPN |
| Google Play | Account exists |
| New requirement | Force upgrade controlled from the admin panel ([ADR-0007](decisions/0007-force-upgrade.md)) |

### Distribution plan for v1 (to confirm in Phase 2)

- **Android:** a Google Play **internal testing** track (up to 100 testers by email) gives normal Play installs and updates. The VPN must be declared in the Play Console (VpnService declaration). A signed APK shared directly is the fallback.
- **iOS:**
  - The owner's own iPhone: development builds from Xcode.
  - Family and friends: **Ad Hoc** builds. Each device's ID must be registered (up to 100 iPhones per membership year), and the build is shared through a download link.
  - TestFlight for external testers and the App Store come after the organization enrollment.
- The force-upgrade `update_url` per platform points to the matching channel.

### Still open

1. ~~Paid Apple Developer Program membership~~: confirmed on 2026-11-16.
2. ~~Approval of the ADRs~~: all approved on 2026-11-16 (0006 as direction).
3. ~~Approval of the [Phase 2 plan](phase2_plan.md)~~: approved 2026-11-17.

## 10. Phase plan

- **Phase 2:**
  - Foundation: git, app rename to PetrikVPN / `cz.tomaspetrik.petrikvpn`.
  - Server setup C2, C3, C8, C4, C5; none of them touches the owner's VPN.
  - Backend skeleton with registration **and the force-upgrade API**.
  - Flutter skeleton with registration **and the force-upgrade gate**.
  - Native-engine spikes.
- **Phase 3:** peer provisioning, Android VPN end to end, internal testing track.
- **Phase 4:** iOS Packet Tunnel end to end, Ad Hoc builds.
- **Phase 5:** admin panel completion (including the app update policy page), hardening, store preparation.
