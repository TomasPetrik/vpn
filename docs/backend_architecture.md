# Backend architecture (Go)

Status: **Proposed.**

## 1. Responsibilities in v1

- Device registration and automatic user creation (idempotent).
- Device-token authentication.
- WireGuard peer provisioning on `wg1` and VPN config delivery.
- Basic server information for the app.
- Minimal admin panel: login, users, devices, peer status, server status.

## 2. Process model

- A single binary `vpn-api` with the subcommands `serve`, `migrate up` and `admin create <username>`.
- Runs as systemd service `vpn-api.service` under user `vpnapi`, with `AmbientCapabilities=CAP_NET_ADMIN` only (needed for netlink access to `wg1`).
- Listens on `127.0.0.1:8090`. Apache terminates TLS for `vpn.radarcut.com` and proxies `/api/` and `/admin/`.
- Background loops run inside the same process:
  - **Reconciler**, on start and every 60 s: makes `wg1` peers equal to the rows in `wireguard_peers`. It owns `wg1` completely and never writes to `wg0`.
  - **Stats poller**, every 30 s: copies last handshake and rx/tx counters from `wg1` into the database.
- The backend never needs the server's WireGuard private key; it reads the public key from the interface.

## 3. Libraries

| Library | Purpose |
| --- | --- |
| `net/http` (Go 1.22+ method/path patterns) | Router; no web framework |
| `database/sql` + `github.com/go-sql-driver/mysql` + `sqlc` (MySQL engine) | MySQL access with generated, typed queries |
| `github.com/pressly/goose/v3` (MySQL dialect) | SQL migrations, embedded in the binary |
| `golang.zx2c4.com/wireguard/wgctrl` | Read and configure `wg1` (and read-only `wg0` status) |
| `golang.org/x/crypto/argon2` | Admin password hashing |
| `github.com/google/uuid` | UUIDv7 for every primary key |
| `log/slog`, `html/template`, `embed` | Logging, admin pages, embedded assets |

## 4. Directory structure

```text
backend/
├── go.mod
├── Makefile                      # build (linux/amd64), sqlc, test, deploy
├── cmd/vpn-api/main.go           # serve | migrate | admin
├── internal/
│   ├── config/                   # env parsing and validation
│   ├── httpapi/                  # router, middleware (request id, logging, recover, rate limit), JSON errors
│   ├── device/                   # registration, device-token auth middleware
│   │   ├── handler.go
│   │   ├── service.go
│   │   └── token.go
│   ├── vpn/                      # peer provisioning, IP allocation, client config
│   │   ├── handler.go
│   │   ├── service.go
│   │   └── ipalloc.go
│   ├── wg/                       # wgctrl adapter (interface + fake for macOS dev), reconciler, stats
│   ├── serverinfo/               # server info and status: load, uptime, wg, wstunnel reachability
│   ├── admin/                    # login, sessions, CSRF, pages
│   │   ├── templates/*.html
│   │   └── static/admin.css
│   └── db/
│       ├── migrations/0001_init.sql
│       ├── queries/*.sql
│       └── sqlc/                 # generated
└── deploy/
    ├── vpn-api.service
    ├── apache-vpn.radarcut.com.conf
    ├── wg1.conf.example          # no keys
    ├── wstunnel-restrictions.yaml
    └── env.example               # names only, no values
```

Layering is handler, then service, then sqlc queries. The only interface is the WireGuard adapter, so services can be tested without netlink. There is no generic repository layer.

## 5. Key flows

### Registration (`POST /api/v1/devices/register`)

1. Validate the input and compute `identifier_hash = HMAC-SHA256(DEVICE_ID_HMAC_KEY, platform + ":" + device_identifier)` when an identifier is present.
2. In one transaction, resolve the device in this order: valid bearer token, then `(platform, identifier_hash)`, then `installation_id`.
3. If a device is found: update its info and missing signals. If the request had no valid token, rotate the token.
4. If no device is found: insert the user and the device. The transaction runs at `READ COMMITTED`. If a concurrent request inserted first, the unique indexes raise a duplicate-key error (1062); that error, or a deadlock (1213), triggers one retry of the lookup, so both requests return the same row.
5. Return the IDs and, when issued, the new token.

### Peer provisioning (`PUT /api/v1/devices/me/peer`)

1. Authenticate the device and validate the public key (base64, 32 bytes).
2. In a transaction, lock the device's active peer row.
   - Same key: return the existing config.
   - Different key: update the key and keep the IP.
   - No peer: allocate the lowest free IP in `10.201.0.0/16` (stored as `INT UNSIGNED`), skipping `.0`, `.1` and the broadcast address. A unique index guards against races; a duplicate-key error retries the allocation.
3. After commit, apply to `wg1` (add or update the peer with `AllowedIPs = <ip>/32`, and remove the old key if it changed).
4. If the kernel apply fails, return `503`; the reconciler converges later. The database is always the source of truth.

## 6. Configuration

`/etc/vpn-api/env` has mode `0640` and owner `root:vpnapi`. Only the variable names are listed here:

```text
HTTP_ADDR=127.0.0.1:8090
DATABASE_DSN
PUBLIC_BASE_URL=https://vpn.radarcut.com
DEVICE_ID_HMAC_KEY
WG_INTERFACE=wg1
WG_TUNNEL_CIDR=10.201.0.0/16
WG_REMOTE=127.0.0.1:51821
WSTUNNEL_URL=wss://vpn.radarcut.com
WSTUNNEL_PATH_PREFIX
SERVER_PUBLIC_IPS=72.61.158.103
VPN_DNS=1.1.1.1,1.0.0.1
VPN_MTU=1280
SERVER_NAME, SERVER_COUNTRY_CODE, SERVER_CITY
```

The MySQL connection uses the Unix socket `/var/run/mysqld/mysqld.sock` with the account `'vpn_app'@'localhost'`, which has privileges only on `vpn.*`. The DSN sets `parseTime=true`, `loc=UTC` and `time_zone='+00:00'`. The socket avoids the `localhost` vs `127.0.0.1` vs `::1` account-host mismatch. The connection pool is capped at 10 (the server allows 151 connections in total).

## 7. Security

- **Device token:** 32 random bytes, base64url. The database stores its SHA-256. Tokens are never logged.
- **Rate limits:** registration per IP; admin login per IP and per username.
- **Proxy headers:** `X-Forwarded-For` is trusted only from `127.0.0.1` (Apache).
- **Admin sessions:**
  - A random 32-byte session ID stored hashed, in cookie `__Host-vpn_admin` (`Secure`, `HttpOnly`, `SameSite=Strict`).
  - 30-minute idle timeout and 12-hour absolute timeout.
  - A CSRF token on every form POST.
  - A strict Content Security Policy.
- **Logging:** never logs device identifiers, tokens or keys. No traffic, DNS or connection logs.

## 8. Admin panel (v1)

All pages are server-rendered, read-only HTML with plain CSS and no JavaScript framework.

| Page | Content |
| --- | --- |
| `/admin/login` | Username and password |
| `/admin` | Server status: uptime, load, `wg1` up and peer count, peers with a handshake in the last 3 minutes, wstunnel port reachable, database OK, read-only `wg0` peer count |
| `/admin/users` | Users with device count and created date (paginated) |
| `/admin/devices` | Platform, model, OS, app version, last seen |
| `/admin/peers` | Device, tunnel IP, last handshake, rx/tx, online/offline |

## 9. Build, deploy, local development

- **Build:** on the Mac, run `GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build`, copy the binary to `/opt/vpn-api/`, run `vpn-api migrate up`, then `systemctl restart vpn-api`. No Go toolchain is needed on the VPS.
- **Local development:** MySQL 8.0 in Docker, the same major version as the VPS (Docker is installed on the Mac); `WG_DRIVER=fake` replaces netlink on macOS. Go still has to be installed on the Mac.
- **Tests:** service unit tests with the fake WireGuard adapter, and query and migration tests against the Docker MySQL.
