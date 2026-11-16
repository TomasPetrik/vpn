# 0002: Dedicated `wg1` interface for app clients

Status: Accepted (2026-11-16)

## Context

`wg0` is hand-managed: one peer (the MacBook), a `/24` subnet, no `SaveConfig`, and NAT rules in `netfilter-persistent`. The backend must add and remove peers automatically. The requirements are to not modify the working VPN and to reuse it where possible.

## Decision

- Create a new interface `wg1`: its own key pair, `10.201.0.1/16`, `ListenPort 51821`, managed by `wg-quick@wg1`.
- UDP 51821 is **not** opened in UFW. Clients reach it only through the separate `wstunnel-app` instance on localhost ([ADR-0001](0001-reuse-wstunnel-transport.md)).
- `wg1.conf` holds no peers. `vpn-api` adds them at runtime with `wgctrl` and reconciles from the database.
- `wg1.conf` carries its own `PostUp`/`PostDown` rules: NAT for `10.201.0.0/16`, forwarding to `eth0`, no access to the host, no client-to-client traffic, no access to `wg0`, and SMTP blocked.
- The reused parts are the WireGuard kernel module and tools, IPv4 forwarding, the NAT pattern, and the installed wstunnel binary.

## Consequences

- `wg0`, its keys, its config and the MacBook tunnel are never touched; a backend bug cannot break the owner's VPN.
- About 65,000 client addresses instead of 253.
- `wg1` can be restarted, or deleted entirely, independently of `wg0`.
- One more interface and one more set of firewall rules to maintain.

## Alternatives considered

- **Add app peers to `wg0` at runtime:** the most reuse, but it mixes manual and automated peers, offers only 253 addresses, and puts the working tunnel at risk.
- **A separate VPS for app clients:** cleanest isolation, but more cost and setup. Revisit when the shared-IP risk (R5) matters.
