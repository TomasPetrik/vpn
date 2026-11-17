# Phase 2 plan

Status: **In progress (2026-11-17).** A–D mostly done. Remaining: owner creates the admin account (D4 password step), then native-engine spikes (E). Admin password is never stored in the repo or docs.

## Goal

At the end of Phase 2:

- **PetrikVPN** runs on the owner's Android phone and iPhone, registers automatically and shows server information. A force upgrade set in the admin panel blocks it.
- The server side for the app is running: `wg1`, `wstunnel-app`, `vpn-api` and `https://vpn.radarcut.com`.
- The native-engine spikes have answered how wstunnel is embedded on each platform.

A real VPN connection from the app is **Phase 3**; in Phase 2 only the spikes connect.

## Safety rules for every server step

- Never restart or edit `wstunnel.service`, `wg-quick@wg0`, `/etc/wireguard/wg0.conf`, `/etc/iptables/rules.v4`, the UFW rules, the `radarcut.com` vhosts or certificate, or the MySQL and PostgreSQL server configuration.
- Before and after each step, check:
  - `wstunnel` was not restarted (start time unchanged since 2026-11-16 08:24:30 UTC),
  - the MacBook answers a ping through `wg0`,
  - `https://radarcut.com` returns 200.
- Back up every file before changing it. The rollback for each change is in [vps_existing_infrastructure.md](vps_existing_infrastructure.md).
- Secrets are generated on the server, stored root-only and never printed. The owner types the admin password himself.

## Steps

### A. Local foundation (Mac only)

| # | Step |
| --- | --- |
| A1 | Repo already on GitHub (`TomasPetrik/vpn`). Extend `.gitignore` for secrets, generated code, keys and keystores. |
| A2 | Install the missing toolchains: Go, `sqlc` and `goose` (backend); Rust via `rustup` with the Android and iOS targets, plus `cargo-ndk` (spikes). Start Docker Desktop for a local MySQL 8.0. |
| A3 | App identity: rename to **PetrikVPN** / `com.petrixon.vpn` (Android `applicationId`, `namespace` and Kotlin package; iOS bundle ID and display name; iOS deployment target 15.0). Verify that it runs on the owner's devices. |

### B. Backend skeleton

| # | Step |
| --- | --- |
| B1 | `backend/` Go module: config, logging, MySQL connection, migration `0001_init.sql` (the full schema from [database.md](database.md)). |
| B2 | API: `/healthz`, `GET /app/config`, `POST /devices/register`, `GET /me`, `GET /servers`; force-upgrade middleware (`426`), device-token auth, rate limiting. |
| B3 | Admin: `vpn-api admin create`, login and logout, sessions, CSRF; pages for status (basic), users, devices and app versions (force-upgrade form). |
| B4 | Tests: services with a fake WireGuard adapter; queries and migrations against Docker MySQL. Includes parallel duplicate registrations (one user, one device) and the `426` path. |

### C. Flutter skeleton

| # | Step |
| --- | --- |
| C1 | Packages and `core/`: DI, Dio with the auth and version interceptors, Drift, secure storage, environment files; router with `/`, `/home` and `/update-required`. |
| C2 | `app_update` feature: check on start and on resume, cached policy, blocking update page, soft prompt. |
| C3 | `device` feature: automatic registration (installation ID, `mobile_device_identifier`, `device_info_plus`). |
| C4 | Home page: server information from `/servers`; the connect button stays disabled until Phase 3. |
| C5 | Tests for the BLoCs and repositories. |

### D. Server (one change at a time, with the safety checks)

| # | Change | Content |
| --- | --- | --- |
| D1 | C2 | MySQL database `vpn`, account `'vpn_app'@'localhost'` |
| D2 | C3 | `wg1`: new key pair, `10.201.0.1/16`, UDP 51821 (local only), its own NAT, isolation and SMTP-block rules; no peers yet |
| D3 | C8 | `wstunnel-app` on `127.0.0.1:8081`: unprivileged user, memory and CPU limits, restriction file (UDP `127.0.0.1:51821` only), secret path prefix |
| D4 | C4 | Deploy `vpn-api` (systemd, env file, migrations). The owner creates his admin account with one command and types the password himself. |
| D5 | C5 | Apache `vpn.radarcut.com`: HTTP vhost, then a separate certbot certificate, then the HTTPS vhost with `/healthz`, `/api/`, `/admin/` and the secret WebSocket path to `127.0.0.1:8081` |
| D6 | — | End to end: the app on the owner's phones registers through `https://vpn.radarcut.com`; the admin panel shows the devices; a minimum build set in the panel blocks the app, and resetting it unblocks it |

### E. Native-engine spikes ([ADR-0006](decisions/0006-native-vpn-engine.md))

| # | Step |
| --- | --- |
| E1 | **Android:** `GoBackend` plus the official wstunnel 10.5.2 Android binary (packaged as `libwstunnel.so`). Connect to `wg1` through `wss://vpn.radarcut.com/<prefix>` with a test peer added by hand. |
| E2 | **iOS:** `PacketTunnel` target with WireGuardKit plus wstunnel as a Rust static library. Same connection; measure the extension's memory on the owner's iPhone. |
| E3 | Results against the ADR-0006 criteria (public IP is the VPS, Wi-Fi to mobile data switch, 30 minutes idle, iOS memory below 40 MB). Record the chosen embedding method in ADR-0006 and remove the test peer. |

## Phase 2 is done when

1. PetrikVPN starts on the owner's Android phone and iPhone, registers automatically and shows "Germany". Reinstalling creates no duplicate user (checked in the admin panel).
2. Force upgrade works end to end, both from the app check and from a `426` on the API.
3. `https://vpn.radarcut.com/admin` has a valid certificate, and login works.
4. The spike results are written down with pass or fail for each criterion.
5. The owner's VPN was never restarted during Phase 2.

## Not in Phase 2

VPN connect and disconnect in the real app, the peer-provisioning API, the admin peers page, and distribution through Play testing or Ad Hoc builds. These come in Phases 3–5.

## Needed from the owner during Phase 2

- Run the admin account command (step D4) and type the password.
- Have the Android phone (USB debugging on) and the iPhone (Developer Mode on, paired in Xcode) at hand for steps A3, D6 and E1–E2.
- Optional: say whether the repository should get a remote (for example GitHub).
