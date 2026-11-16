# Architecture decision records

Each record has a status of Proposed, Accepted, Superseded or Rejected. All records below were approved by the owner on 2026-11-16.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-reuse-wstunnel-transport.md) | wstunnel as the mobile transport, in a separate instance for the app | Accepted |
| [0002](0002-dedicated-wg1-interface.md) | Dedicated `wg1` interface for app clients | Accepted |
| [0003](0003-client-generated-wireguard-keys.md) | WireGuard keys are generated on the device | Accepted |
| [0004](0004-device-recognition-and-authentication.md) | Device recognition vs. authentication | Accepted |
| [0005](0005-backend-hosting-and-admin.md) | Backend hosting and admin panel | Accepted |
| [0006](0006-native-vpn-engine.md) | Native VPN engine with an embedded wstunnel client | Accepted as direction; embedding method finalized after the Phase 2 spikes |
| [0007](0007-force-upgrade.md) | Force upgrade controlled from the admin panel | Accepted |
