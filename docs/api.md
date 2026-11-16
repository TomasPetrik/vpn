# API proposal

Status: **Proposed.** The base URL is `https://vpn.radarcut.com/api/v1`. All bodies are JSON (`snake_case`).

## Conventions

- **Auth:** `Authorization: Bearer <device_token>` on every endpoint marked with an asterisk (*).
- **Errors:** `{"error": {"code": "invalid_request", "message": "..."}}`. Codes: `invalid_request` (400), `invalid_token` (401), `device_blocked` (403), `not_found` (404), `rate_limited` (429), `wg_unavailable` (503), `internal` (500).
- **Idempotency:** registration and peer provisioning can be retried safely; they never create duplicates.

## Endpoints

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/healthz` (outside `/api/v1`) | none | Liveness for monitoring |
| POST | `/devices/register` | optional | Recognize or create the device and user, issue a token |
| GET | `/me` | * | Current user and device |
| PUT | `/devices/me/peer` | * | Provision or update the WireGuard peer, return the VPN config |
| GET | `/devices/me/peer` | * | Current VPN config (404 if none) |
| GET | `/servers` | * | Basic server information |

### `POST /devices/register`

Request:

```json
{
  "installation_id": "3f1c9a52-0b7e-4c1e-9d0a-2b9c7d1e5f10",
  "device_identifier": "string or null",
  "platform": "android",
  "device": {
    "manufacturer": "Google",
    "model": "Pixel 8",
    "os_version": "15",
    "is_physical_device": true
  },
  "app": { "version": "1.0.0", "build": "1" }
}
```

Response: `201` when created, `200` when recognized:

```json
{
  "user_id": "0193f1e2-...",
  "device_id": "0193f1e2-...",
  "device_token": "only present when a new token was issued",
  "created": false
}
```

Rules:

- With a valid bearer token for the same device, the response contains no `device_token`; the client keeps its current one.
- Without a valid token (for example after a reinstall), a recognized device gets a **new** token and the old one stops working.
- `device_identifier` is optional and is never used as proof of identity.

### `PUT /devices/me/peer`

Request:

```json
{ "public_key": "base64 32-byte WireGuard public key" }
```

Response `200`:

```json
{
  "peer_id": "0193f1e2-...",
  "server": { "id": "0193f1e2-...", "name": "EU-1", "country_code": "??" },
  "interface": {
    "addresses": ["10.201.0.17/32"],
    "dns": ["1.1.1.1", "1.0.0.1"],
    "mtu": 1280
  },
  "peer": {
    "public_key": "server wg1 public key",
    "allowed_ips": ["0.0.0.0/0", "::/0"],
    "excluded_ips": ["72.61.158.103/32"],
    "persistent_keepalive": 25
  },
  "transport": {
    "type": "wstunnel",
    "url": "wss://vpn.radarcut.com",
    "path_prefix": "<prefix>",
    "remote": "127.0.0.1:51821",
    "server_ips": ["72.61.158.103"]
  }
}
```

Rules:

- The same key returns the same peer and IP. A new key replaces the old key and keeps the IP.
- The client sets its WireGuard endpoint to the local wstunnel listener (`127.0.0.1:<port>`).
- `server_ips` lets the client connect without DNS while the tunnel is starting, using SNI and Host `vpn.radarcut.com`.

### `GET /servers`

```json
{
  "servers": [
    { "id": "0193f1e2-...", "name": "EU-1", "country_code": "??", "city": null, "status": "online" }
  ]
}
```

## Admin (HTML, not part of the public API)

| Method | Path | Purpose |
| --- | --- | --- |
| GET, POST | `/admin/login` | Login form and submit (rate limited) |
| POST | `/admin/logout` | End the session |
| GET | `/admin` | Server status |
| GET | `/admin/users` | Users list |
| GET | `/admin/devices` | Devices list |
| GET | `/admin/peers` | WireGuard peer status |

## Later (not in v1)

`DELETE /devices/me/peer` (revoke), connection event reporting, multiple servers, and app attestation on register.
