# Existing VPS infrastructure

Audit date: 2026-11-16. The audit was **read-only**: no service was restarted, no file was changed, no key was read in clear. Private keys were stripped on the server before any output left it. Public keys and client IP addresses are intentionally omitted from this document.

## 1. Host

| Item | Value |
| --- | --- |
| Provider | Hostinger VPS (KVM), hostname `srv1261775` |
| Public IPv4 | `72.61.158.103` (gateway `72.61.158.254`) |
| Public IPv6 | `2a02:4780:41:792a::1/48` |
| OS | Ubuntu 24.04.3 LTS, kernel 6.8.0-147 |
| Resources | 2 vCPU, 7.8 GiB RAM, 96 GB disk (16 GB used) |
| Access | SSH as `root` with key from the MacBook |
| Datacenter / bandwidth quota | Unknown (not visible from the shell or the Hostinger API tools available) |

## 2. WireGuard (`wg0`)

- `wireguard-tools` v1.0.20210914 with the kernel module; `wg-quick@wg0` enabled, up since 2026-10-17.
- `/etc/wireguard/wg0.conf`: `Address = 10.200.200.1/24`, `ListenPort = 51820`. No `SaveConfig`, no `PostUp`/`PostDown`, no DNS.
- One peer: the owner's MacBook, `10.200.200.2/32`, handshaking every few minutes, about 4.5 GiB transferred in each direction.
- Key files `wg-vps.key` / `wg-vps.pub` live in `/etc/wireguard` (directory mode `0700`).
- UDP 51820 listens on all interfaces and is allowed by UFW, so plain WireGuard is also reachable directly.

## 3. wstunnel

- Binary `/root/wstunnel`, version **10.5.2**, runs as `root`.
- Unit `/etc/systemd/system/wstunnel.service`: `ExecStart=/root/wstunnel server ws://0.0.0.0:8080`, `Restart=always`.
- Plain WebSocket (no TLS). No `--restrict-to`, no path-prefix restriction, no restriction file. The log confirms every tunnel is accepted by the built-in rule `Allow All`.
- MacBook client:

  ```bash
  wstunnel client \
    -L 'udp://51820:127.0.0.1:51820?timeout_sec=0' \
    --connection-retry-max-backoff 1h \
    --websocket-ping-frequency 30s \
    ws://72.61.158.103:8080
  ```

  The MacBook WireGuard peer endpoint is `127.0.0.1:51820`. The user-readable copy of the client config (`~/workspace/wireguard/wg0.conf`) routes only `10.200.200.1/32`. The active config `/opt/homebrew/etc/wireguard/wg0.conf` is root-only and was not read. Whether the MacBook uses a full tunnel is unknown.
- Internet scanners already probe port 8080 (the log shows a rejected HTTP/1.0 probe).

Current data path:

```text
MacBook WireGuard -> 127.0.0.1:51820 (local wstunnel client)
  -> ws://72.61.158.103:8080 (wstunnel server)
  -> UDP 127.0.0.1:51820 -> wg0 -> NAT on eth0 -> internet
```

## 4. Network, routing, firewall

- Interfaces: `eth0` (public), `wg0` `10.200.200.1/24`, `docker0` `172.17.0.1/16` (down, no containers).
- `net.ipv4.ip_forward = 1` (set in `/etc/sysctl.conf`). IPv6 forwarding is off; there is no IPv6 NAT.
- UFW is active: default deny incoming, allow outgoing, deny routed. Allowed inbound (v4 and v6): `22/tcp`, `80/tcp`, `443/tcp`, `8080/tcp`, `8000/tcp`, `51820/udp`.
- WireGuard NAT and forwarding (iptables-nft):

  ```text
  -t nat -A POSTROUTING -s 10.200.200.0/24 -o eth0 -j MASQUERADE
  -A FORWARD -i wg0 -o eth0 -j ACCEPT
  -A FORWARD -i eth0 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ```

  These rules are persisted in `/etc/iptables/rules.v4` by `netfilter-persistent` (enabled), not in `wg0.conf` or UFW's files.

## 5. Listening services

| Port | Process | Exposure |
| --- | --- | --- |
| 22/tcp | sshd | public |
| 80, 443/tcp | apache2 | public |
| 8080/tcp | wstunnel | public |
| 51820/udp | WireGuard `wg0` | public |
| 3000/tcp | next-server (radarcut) | bound on all interfaces, blocked by UFW |
| 3306, 33060/tcp | mysqld | localhost |
| 5432/tcp | PostgreSQL 16 | localhost |
| 53 | systemd-resolved | localhost |

## 6. Other workloads on the same VPS (must not be disturbed)

- **Apache 2.4** serves `radarcut.com` and `www.radarcut.com` on 80/443 with a Let's Encrypt certificate (certbot, expires 2027-02-10). Enabled modules include `proxy`, `proxy_http`, `ssl`, `rewrite` and `headers`. `proxy_wstunnel` and `http2` are available but not enabled.
- **radarcut.service**: Next.js 16 app (`npm run start -- -p 3000`, user `radarcut`).
- **PostgreSQL 16.15**, listening on localhost only. Databases: `radarcut`, `symfony_demo`.
- **MySQL** and **PHP 8.3-FPM** (localhost).
- **Docker** engine with no running containers.
- Disabled units: `tg-bot`, `tg-telethon`, `tg-telethon-web`.

## 7. DNS

- `petrixon.com` uses Websupport.sk nameservers (`ns1-3.websupport.sk`).
- `vpn.petrixon.com` has no record of its own. It matches a wildcard pointing to Websupport hosting (`37.9.175.132`, `2a00:4b40:aaaa:2001::5`), **not** to the VPS.
- Required: an explicit `A vpn.petrixon.com -> 72.61.158.103` record. Once the name has its own record, the wildcard AAAA no longer applies to it. Add an AAAA record only after IPv6 is handled end to end.

## 8. Findings in the current setup (not changed)

| # | Severity | Finding |
| --- | --- | --- |
| F1 | Critical | **wstunnel is an open relay.** Anyone can open tunnels through `:8080` to any destination. That includes services bound to the VPS's localhost (PostgreSQL 5432, MySQL 3306, Next.js 3000), SOCKS5 and HTTP proxying, and reverse tunnels that bind ports on the server (port 8000 is open in UFW and unused). It runs as root. Abuse would land on this IP and on `radarcut.com`. |
| F2 | High | Plain `ws://`: the upgrade request and tunnel metadata are visible to DPI and easy to fingerprint. |
| F3 | Medium | VPN egress shares one IP with `radarcut.com`. Blocklisting or abuse reports against the VPN IP affect the website, and the reverse is also true. |
| F4 | Low | UFW and `netfilter-persistent` both manage iptables. Running `netfilter-persistent save` would capture UFW's chains into `rules.v4`. New rules should be self-contained (see section 9, change C3). |
| F5 | Low | `wg-vps.key` has mode `0644`. The `0700` directory mitigates this. |
| F6 | Info | UFW allows `8000/tcp`, but nothing listens on it. |

## 9. Reuse plan

**Reused as is:** WireGuard kernel module and tools, the wstunnel server process (and binary version), IPv4 forwarding, the NAT/forward rule pattern, UFW, Apache with certbot, and PostgreSQL 16.

**Never touched:** `wg0`, its peer, its keys and `wg0.conf`; `radarcut` (Apache vhost, app and database); MySQL; the other databases.

**Proposed additive changes.** Each one needs your explicit approval before it is applied, is applied separately, and is verified before the next:

| # | Change | Effect on the working VPN | Rollback |
| --- | --- | --- | --- |
| C1 | DNS at Websupport: `A vpn.petrixon.com 72.61.158.103` | none | delete the record |
| C2 | PostgreSQL: role `vpn_app`, database `vpn` | none | `DROP DATABASE vpn; DROP ROLE vpn_app;` |
| C3 | New interface `wg1`: new key pair, `10.201.0.1/16`, `ListenPort 51821` (no UFW rule, so reachable only via wstunnel on localhost). `PostUp`/`PostDown` add and remove its own NAT, forward, isolation and SMTP-block rules. | none, `wg0` untouched | `systemctl disable --now wg-quick@wg1`, remove `wg1.conf` |
| C4 | `vpn-api` systemd service: user `vpnapi`, `127.0.0.1:8090`, `CAP_NET_ADMIN` only | none | `systemctl disable --now vpn-api` |
| C5 | Apache vhost `vpn.petrixon.com` with a certbot certificate. `/api` and `/admin` proxy to `127.0.0.1:8090`; `/<secret-prefix>/` proxies WebSocket upgrades to `127.0.0.1:8080`. Run `apache2ctl configtest` before a graceful reload. | none, `radarcut` vhost untouched | `a2dissite`, graceful reload |
| C6 | **wstunnel hardening (fixes F1).** Add `--restrict-config /etc/wstunnel/restrictions.yaml` to the unit, allowing only UDP to `127.0.0.1` ports 51820 and 51821. Requires **one wstunnel restart** (about 5 s MacBook reconnect); no MacBook client change. | brief reconnect | restore the unit backup, `daemon-reload`, restart |
| C7 | Later: bind wstunnel to `127.0.0.1:8080`, require the secret path prefix, and close 8080 in UFW. Needs the MacBook client to move to `wss://vpn.petrixon.com/<prefix>`. | MacBook client command change | revert the unit, reopen 8080 |

Sketch for C6 (to be verified on the server before applying):

```yaml
restrictions:
  - name: "wireguard-only"
    match: [!PathPrefix "^.*$"]
    allow:
      - !Tunnel
        protocol: [Udp]
        port: [51820, 51821]
        cidr: [127.0.0.1/32]
```

Sketch for C3 rules (managed by `wg1.conf`, so they leave together with the interface):

```text
PostUp = iptables -A FORWARD -i wg1 -o eth0 -p tcp --dport 25 -j DROP
PostUp = iptables -A FORWARD -i wg1 -o eth0 -j ACCEPT
PostUp = iptables -A FORWARD -i eth0 -o wg1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostUp = iptables -I INPUT -i wg1 -j DROP
PostUp = iptables -t nat -A POSTROUTING -s 10.201.0.0/16 -o eth0 -j MASQUERADE
# PostDown mirrors each line with -D
```

No rule allows `wg1 -> wg1` or `wg1 -> wg0` forwarding, so the `FORWARD DROP` policy blocks client-to-client traffic and access to the MacBook tunnel.

## 10. Read-only commands used

All commands were run over `ssh root@72.61.158.103`. Key material was redacted with `sed` on the server.

```bash
cat /etc/os-release; uname -r; nproc; free -h; df -h /; systemd-detect-virt
systemctl list-units --type=service --state=running
systemctl list-unit-files --state=enabled
wg show all                                   # private key shown as (hidden); public keys redacted
sed -E 's/^(PrivateKey|PresharedKey).*/\1 = <redacted>/' /etc/wireguard/wg0.conf
systemctl status 'wg-quick@*' wstunnel.service; systemctl cat wstunnel.service
/root/wstunnel --version
ss -tulpn; ip -br addr; ip route; ip -6 route
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
ufw status verbose; iptables -S; iptables -t nat -S; ip6tables -t nat -S; nft list tables
apache2ctl -S; apache2ctl -M; ls /etc/letsencrypt/live
sudo -u postgres psql -c 'select version()'   # plus database and role names only
docker ps; systemctl show radarcut.service
```

Locally: `dig vpn.petrixon.com`, `dig NS petrixon.com`, and the redacted `~/workspace/wireguard/wg0.conf`.
