# 0004: Device recognition vs. authentication

Status: Proposed

## Context

Users are created automatically, without login. The app can read `mobile_device_identifier`: a MediaDrm-based UUID on Android and a Keychain UUID on iOS (package v0.1.0, unverified publisher). The identifier may be missing, may change, and can be spoofed, so it cannot be used for authentication.

## Decision

- **Recognition signals:**
  - `installation_id`: a random UUID created by the app and kept in secure storage.
  - `device_identifier`: optional.
  - The backend stores only `HMAC-SHA256(server key, platform:identifier)`, never the raw value.
- **Authentication:** the backend issues an opaque random device token on registration. The client keeps it in secure storage and sends it as a bearer token. The backend stores only its SHA-256 hash.
- **Resolution order:** valid token, then identifier hash, then `installation_id`, then create a new user and device. Unique indexes and a single transaction guarantee there are no duplicates.
- A recognized device without a valid token (for example after a reinstall) receives a **new** token, and the old token is invalidated.
- The backend generates the user and device UUIDs (UUIDv7).

## Consequences

- Reinstalls usually map back to the same user and device.
- Someone who knows another device's identifier can take over that device record (and get a VPN config). This is accepted for a free v1 with no personal data, and documented as risk R9.
- Before payments or subscriptions, add App Attest / Play Integrity or real account login.

## Alternatives considered

- **Identifier as the only credential:** rejected (spoofable, not permanent).
- **Anonymous token only, without recognition:** reinstalls would create duplicate users, which goes against the requirements.
