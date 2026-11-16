# 0001: Reuse the existing wstunnel server as the mobile transport

Status: Proposed

## Context

Plain WireGuard over UDP is blocked or fingerprinted on the networks this app targets. The existing wstunnel 10.5.2 server already carries WireGuard for the MacBook over `ws://72.61.158.103:8080`. That endpoint uses no TLS and has no restrictions (finding F1).

## Decision

- Mobile clients run WireGuard through an embedded wstunnel client against the **same wstunnel server process**.
- Clients reach it as `wss://vpn.radarcut.com/<secret-prefix>` on port 443. Apache terminates TLS with a Let's Encrypt certificate and proxies the WebSocket upgrade to `127.0.0.1:8080`. The wstunnel server itself is not changed for this.
- The existing `ws://...:8080` endpoint stays for the MacBook until it migrates (change C7).
- Before any app traffic, wstunnel gets a restriction file that allows only UDP to `127.0.0.1:51820` and `127.0.0.1:51821` (change C6).
- Client and server stay pinned to wstunnel 10.5.2 and are upgraded together.

## Consequences

- Reuses working infrastructure and adds no new server-side tunnel software.
- TLS on 443 with a real certificate is harder to fingerprint than `ws://` on 8080.
- WireGuard over TCP is slower on lossy networks (TCP-over-TCP), so MTU 1280 is used.
- One domain and one IP carry both the API and the tunnel; blocking either breaks both.

## Alternatives considered

- **Direct WireGuard UDP:** simplest, but blocked for the target users.
- **AmneziaWG or Xray/VLESS:** stronger obfuscation, but a new stack that ignores the existing infrastructure. Kept as a future option.
- **Expose wstunnel's own TLS on another port:** works, but needs certificate handling in wstunnel and an extra open port.
