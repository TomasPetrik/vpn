# 0003: WireGuard keys are generated on the device

Status: Accepted (2026-11-16)

## Context

Each device needs a WireGuard key pair. If the server generates keys, private keys exist on the server and travel over the network.

## Decision

- The native engine generates the key pair on first use with the WireGuard library's key generator: `com.wireguard.crypto.KeyPair` on Android, WireGuardKit `PrivateKey` on iOS.
- The private key is stored only in native secure storage: Android Keystore-backed encryption, or a Keychain access group shared with the Packet Tunnel extension. It is never passed to Dart and never sent to the server.
- The app sends only the public key (`PUT /devices/me/peer`). Rotating the key means generating a new pair and sending the new public key; the server keeps the same tunnel IP.

## Consequences

- A database or backend compromise does not reveal client private keys.
- Reinstalling the app on Android loses the key, so a new key is registered and replaces the old peer.
- Key generation lives in native code, which adds a little to the native bridge.

## Alternatives considered

- **Server-generated keys returned in the config:** simpler client, worse security.
- **Dart-side generation (`cryptography` package) with `flutter_secure_storage`:** workable, but the key would pass through Dart memory and platform channels.
