# Flutter architecture

Status: **Proposed.** The project is currently the default Flutter template (`cz.scalesoft.ru_eu_vpn` on Android, `cz.scalesoft.ruEuVpn` on iOS, Dart SDK `^3.10.4`, iOS deployment target 13.0).

## 1. Principles

- **Feature-first.** Code is grouped by feature. Each feature has `data/`, `domain/` and `presentation/`.
- **Lightweight Clean Architecture.**
  - `domain/` holds entities (Freezed) and repository interfaces, and does not depend on Flutter, Dio or Drift.
  - Use cases exist only when a flow coordinates several repositories (`ConnectVpn`). Otherwise BLoCs call repositories directly.
  - `data/` holds Retrofit APIs, DTOs, Drift DAOs, platform channels and repository implementations. DTOs are mapped to entities inside the repository, without separate mapper classes.
- `core/` holds only cross-cutting infrastructure: DI, network, database, secure storage and config.
- A feature never imports another feature's `data/`. Cross-feature needs go through a domain interface registered in DI.
- One BLoC per screen-level concern. A `Cubit` is used where events would add nothing.

## 2. Packages

| Package | Purpose |
| --- | --- |
| `flutter_bloc` | State management |
| `go_router` | Navigation |
| `dio`, `retrofit` | HTTP client and typed APIs |
| `drift`, `drift_flutter` | Local cache (registration, servers, last VPN config) |
| `freezed_annotation`, `json_annotation` | Entities, states, DTOs |
| `get_it`, `injectable` | Dependency injection |
| `device_info_plus`, `mobile_device_identifier` | Device recognition signals |
| `flutter_secure_storage` (addition) | Device token and installation ID; Drift is not encrypted |
| `package_info_plus` (addition) | App version sent at registration |
| `uuid` (addition) | Installation ID |
| Dev: `build_runner`, `freezed`, `json_serializable`, `retrofit_generator`, `injectable_generator`, `drift_dev`, `bloc_test`, `mocktail` | Code generation and tests |

No VPN plugin from pub.dev: `wireguard_flutter` (last release about two years ago) has no wstunnel support. The app owns a small native bridge instead (section 8).

## 3. Directory structure

```text
lib/
├── main.dart
├── app/
│   ├── app.dart                     # MaterialApp.router, theme
│   ├── router.dart                  # GoRouter: /, /home
│   └── bootstrap.dart               # DI, database, error handling
├── core/
│   ├── di/
│   │   ├── injection.dart           # @InjectableInit -> injection.config.dart
│   │   └── register_module.dart     # Dio, AppDatabase, secure storage, device info
│   ├── config/app_config.dart       # API base URL from --dart-define-from-file
│   ├── network/
│   │   ├── dio_factory.dart
│   │   ├── auth_interceptor.dart    # Bearer device token, one re-register on 401
│   │   └── api_failure.dart         # sealed Failure: network, server, unauthorized, unknown
│   ├── database/
│   │   └── app_database.dart        # Drift DB and tables
│   └── storage/
│       └── secure_store.dart        # device token, installation id
└── features/
    ├── device/                      # first launch and automatic registration
    │   ├── data/
    │   │   ├── device_api.dart              # Retrofit: POST /devices/register, GET /me
    │   │   ├── device_info_source.dart      # mobile_device_identifier + device_info_plus
    │   │   ├── dtos/register_dtos.dart
    │   │   └── device_repository_impl.dart
    │   ├── domain/
    │   │   ├── device_registration.dart     # entity: userId, deviceId
    │   │   └── device_repository.dart
    │   └── presentation/
    │       ├── bootstrap_cubit.dart
    │       └── splash_page.dart
    ├── vpn/                         # connect, disconnect, status
    │   ├── data/
    │   │   ├── vpn_api.dart                 # Retrofit: PUT/GET /devices/me/peer
    │   │   ├── vpn_engine_channel.dart      # MethodChannel + EventChannel bridge
    │   │   ├── dtos/vpn_config_dto.dart
    │   │   └── vpn_repository_impl.dart
    │   ├── domain/
    │   │   ├── vpn_config.dart
    │   │   ├── vpn_status.dart              # Freezed union
    │   │   ├── vpn_repository.dart
    │   │   └── connect_vpn.dart             # registered -> key -> provision -> permission -> start
    │   └── presentation/
    │       ├── vpn_bloc.dart                # + vpn_event.dart, vpn_state.dart
    │       ├── home_page.dart
    │       └── widgets/ (connect_button.dart, status_card.dart)
    └── servers/                     # basic server info
        ├── data/ (servers_api.dart, servers_repository_impl.dart)
        ├── domain/ (vpn_server.dart, servers_repository.dart)
        └── presentation/ (server_info_cubit.dart, server_info_card.dart)
```

Generated files (`*.g.dart`, `*.freezed.dart`, `injection.config.dart`) are produced with `dart run build_runner build -d` and kept out of git.

## 4. Navigation

- `/`: `SplashPage` waits for `BootstrapCubit`, then redirects to `/home`.
- `/home`: `HomePage` with the connect button, status and server info.

These are the only two routes in v1.

## 5. State

- **`BootstrapCubit`** (device feature) moves through `initial`, `registering`, then `registered` or `offline`. A failure does not block the home screen; registration is retried on connect.
- **`VpnBloc`** (vpn feature) handles the events `ConnectPressed`, `DisconnectPressed` and `EngineStatusChanged`. Its state is a `VpnStatus` union: `disconnected`, `preparing`, `permissionDenied`, `connecting`, `connected(since, tunnelIp, rx, tx)`, `disconnecting` and `failed(reason)`.
- **`ServerInfoCubit`** (servers feature) shows the cached server first, then refreshes it from `GET /servers`.

## 6. Local data

| Data | Storage |
| --- | --- |
| Device token, installation ID | `flutter_secure_storage` (Keychain, Android Keystore) |
| WireGuard private key | Native secure storage only; never passed to Dart |
| `user_id`, `device_id`, server list, last VPN config (public parts) | Drift tables `registration`, `servers`, `vpn_profile` |

## 7. Device identity collection

```dart
final deviceId = await MobileDeviceIdentifier().getDeviceId();
```

- Wrapped in `DeviceInfoSource`. Any exception or empty value becomes `null`, and registration continues with the installation ID alone.
- `device_info_plus` provides the platform, manufacturer, model, OS version and whether the device is physical.
- The installation ID is a UUID v4 created on first launch and kept in secure storage.
- The raw identifier is sent only over HTTPS. The backend stores only an HMAC of it.

## 8. Native VPN engine (iOS and Android integration plan)

### Dart contract

The bridge uses MethodChannel `vpn_engine` and EventChannel `vpn_engine/status`:

| Method | Purpose |
| --- | --- |
| `getPublicKey()` | Creates the key pair natively if missing and returns the public key |
| `prepare()` | Asks for OS VPN permission; returns whether it was granted |
| `connect(config)` | Starts the wstunnel client, then WireGuard. The config has no private key. |
| `disconnect()` | Stops WireGuard, then wstunnel |
| `getStatus()` | Returns the status, rx/tx bytes and last handshake |

The status events are `disconnected`, `connecting`, `connected`, `disconnecting` and `error(code)`.

### Android

- `com.wireguard.android:tunnel` (`GoBackend`, wireguard-go on top of `VpnService`). Its service is declared with `BIND_VPN_SERVICE`.
- Permission through `VpnService.prepare()`; the activity result goes back to Dart.
- wstunnel client options (Phase 2 spike):
  - A: the official Android build of wstunnel 10.5.2, packaged as `libwstunnel.so` in `jniLibs` and run from `nativeLibraryDir`.
  - B: a Rust FFI wrapper built with `cargo-ndk`.
- Routing-loop prevention: AllowedIPs is `0.0.0.0/0` minus the server IP (the backend sends `excluded_ips`). `::/0` is routed into the tunnel to block IPv6 leaks.
- A foreground notification while connected. The Android 14+ foreground-service type still needs verifying. The private key is stored with Keystore-backed encryption.

### iOS

- Requires the paid Apple Developer team (`RL5SKRM28G` is already set), the Network Extension capability (Packet Tunnel), an App Group and a shared Keychain access group.
- New Xcode target `PacketTunnel` (`NEPacketTunnelProvider`) using WireGuardKit from wireguard-apple. Its wireguard-go bridge needs the Go toolchain during the Xcode build.
- The wstunnel client is compiled from Rust as an XCFramework and started inside the extension before WireGuard, which uses endpoint `127.0.0.1:<port>`.
- The extension's memory limit (about 50 MB) is measured in the spike. The minimum iOS version is likely raised to 15.
- The app side uses `NETunnelProviderManager` to install, start and stop the tunnel; `NEVPNStatusDidChange` feeds the EventChannel.
- Testing requires physical devices; the Simulator cannot run packet tunnels.

### Fallback

If embedding wstunnel proves impractical, the wstunnel client protocol (WebSocket upgrade plus UDP framing) can be implemented as a custom `conn.Bind` inside the wireguard-go bridge. That gives one Go runtime and no loopback UDP, at the cost of more custom code and compatibility testing against server 10.5.2.

## 9. Configuration and testing

- Environments use `--dart-define-from-file=env/dev.json` or `env/prod.json` (`API_BASE_URL`).
- BLoCs are tested with `bloc_test` and `mocktail`; repositories are tested with fake APIs. The native engine is tested manually on devices.
