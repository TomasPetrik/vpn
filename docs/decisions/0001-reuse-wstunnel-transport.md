# 0001: wstunnel as the mobile transport, in a separate instance for the app

Status: Accepted (2026-11-16)

## Context

Plain WireGuard over UDP is blocked or throttled on some networks (certain ISPs, public and corporate Wi-Fi). The installed wstunnel 10.5.2 already carries WireGuard for the MacBook over `ws://72.61.158.103:8080`. Since change C6 it is restricted to UDP `127.0.0.1:51820`.

All of the owner's internet traffic, including work sessions, goes through that wstunnel process. Every restart of it interrupts the owner.

## Decision

- Mobile clients run WireGuard through an embedded wstunnel client against a **separate wstunnel server instance**, the systemd service `wstunnel-app`.
  - It uses the already installed wstunnel 10.5.2 binary, or its own copy if the app ever needs a different version.
  - It listens only on `127.0.0.1:8081` and is not exposed directly to the internet.
  - It runs as an unprivileged user with systemd resource limits.
  - Its restriction file `/etc/wstunnel-app/restrictions.yaml` allows only UDP to `127.0.0.1:51821` (`wg1`).
- Phones reach it as `wss://vpn.radarcut.com/<secret-prefix>` on port 443. Apache terminates TLS with a Let's Encrypt certificate and proxies only that path to `127.0.0.1:8081`.
- The owner's instance (`wstunnel` on `:8080`, `wg0`) stays as it is and is never restarted for app reasons. Moving the MacBook to `wss://` later (C7) is optional and independent.
- The app's client and server stay pinned to the same wstunnel version and are upgraded together.

## Consequences

- App changes, restarts, upgrades and incidents cannot interrupt the owner's VPN.
- Phones cannot reach `wg0`, and the MacBook path cannot reach `wg1`.
- TLS on 443 with a real certificate is harder to fingerprint than `ws://` on 8080.
- One more service and configuration file to maintain, using about 10–20 MB of RAM.
- WireGuard over TCP is slower on lossy networks (TCP-over-TCP), so MTU 1280 is used.
- One domain and one IP carry both the API and the app tunnel; blocking either breaks both.

## Alternatives considered

- **Share the owner's wstunnel instance** (add port 51821 to its restriction file): works without a restart, but later app changes (TLS, path prefix, upgrades) would restart the process that carries the owner's traffic.
- **Direct WireGuard UDP:** simplest, but blocked on some networks.
- **AmneziaWG or Xray/VLESS:** stronger obfuscation, but a new stack that ignores the existing infrastructure. Kept as a future option.
