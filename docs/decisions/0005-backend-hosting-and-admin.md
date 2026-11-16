# 0005: Backend hosting and admin panel

Status: Accepted (2026-11-16)

## Context

The Hostinger VPS already runs Apache (which owns 80/443 and serves `radarcut.com`), certbot, MySQL 8.0 and PostgreSQL 16. The owner chose MySQL for this project (2026-11-16). The admin panel needs only login and a few read-only lists.

## Decision

- **One Go binary `vpn-api`** serves the REST API, the admin panel and the background loops (reconciler and stats poller).
  - It runs under systemd as user `vpnapi` with only `CAP_NET_ADMIN`, on `127.0.0.1:8090`.
- **Apache** gets a new vhost `vpn.radarcut.com` with its own certbot certificate. It proxies `/api/` and `/admin/` to `vpn-api`, and the secret WebSocket path to `wstunnel-app` on `127.0.0.1:8081`. The `radarcut` vhost is untouched; config changes go through `configtest` and a graceful reload.
- **MySQL:** a new database `vpn` with a dedicated account `'vpn_app'@'localhost'`, on the existing MySQL 8.0 server, reached over the Unix socket. The server configuration is not changed.
- **Admin panel:** server-rendered `html/template` pages embedded in the binary, with no JavaScript framework and no separate frontend build.
- **Deployment:** cross-compile on the Mac and copy the binary to the VPS. No Go toolchain and no Docker are needed on the server.

## Consequences

- No new ports are exposed, and no new web server or database server is needed.
- One process to deploy and monitor.
- The VPN backend shares Apache with `radarcut` and MySQL with `symfony_demo`. A misconfiguration could affect them, which is mitigated by `configtest`, separate vhost files and a separate database account.
- MySQL has no partial indexes and no `inet` or `uuid` types, so the schema uses one peer row per device, `INT UNSIGNED` IPs and `CHAR(36)` UUIDs (see [database.md](../database.md)).

## Alternatives considered

- **Docker containers:** a cleaner boundary, but Docker's iptables handling next to UFW and `netfilter-persistent` adds risk, and `wgctrl` would need host networking anyway.
- **A separate SPA admin (React or Flutter web):** more work than the scope needs.
- **Caddy or nginx:** would have to share 80/443 with the existing Apache.
- **PostgreSQL 16 (also installed):** richer types (`inet`, `uuid`, partial indexes), but the owner prefers MySQL.
