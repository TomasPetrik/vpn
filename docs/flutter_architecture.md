# Flutter architecture

Status: **Proposed.** The project is currently the default Flutter template (`cz.scalesoft.ru_eu_vpn` on Android, `cz.scalesoft.ruEuVpn` on iOS, Dart SDK `^3.10.4`, iOS deployment target 13.0).

## 0. App identity (decided 2026-11-16, applied in Phase 2)

| Item | Value |
| --- | --- |
| Display name | **PetrikVPN** |
| Android `applicationId` and `namespace` | `com.petrixon.vpn` (Kotlin sources move to `com/petrixon/vpn/`) |
| iOS bundle ID | `com.petrixon.vpn` |
| iOS Packet Tunnel extension | `com.petrixon.vpn.PacketTunnel` (must be prefixed by the app's bundle ID) |
| iOS App Group / Keychain group | `group.com.petrixon.vpn` |
| Dart package name | stays `ru_eu_vpn` (internal only, never shown to users) |

The IDs must be final before the first build reaches anyone. After that, a change means a new app for the stores and for the force-upgrade policy.

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
| `device_info_plus`, `mobile_device_identifier` (^0.0.3; 0.1.x needs Flutter ≥3.41) | Device recognition signals |
| `flutter_secure_storage` (addition) | Device token and installation ID; Drift is not encrypted |
| `package_info_plus` (addition) | App version and build number (registration, force upgrade) |
| `url_launcher` (addition) | Opens the update link from the force-upgrade page |
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
│   │   ├── app_version_interceptor.dart  # X-App-Platform/Build/Version headers; 426 -> force upgrade
│   │   └── api_failure.dart         # sealed Failure: network, server, unauthorized, unknown
│   ├── database/
│   │   └── app_database.dart        # Drift DB and tables
│   └── storage/
│       └── secure_store.dart        # device token, installation id
└── features/
    ├── app_update/                  # force and soft upgrade (ADR-0007)
    │   ├── data/
    │   │   ├── app_config_api.dart          # Retrofit: GET /app/config
    │   │   └── app_update_repository_impl.dart  # caches the last policy in Drift
    │   ├── domain/
    │   │   ├── update_policy.dart           # Freezed: none | recommended | required
    │   │   └── app_update_repository.dart
    │   └── presentation/
    │       ├── app_update_cubit.dart        # checks on start and on resume
    │       ├── update_required_page.dart    # full-screen block with the update button
    │       └── update_available_banner.dart
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

- `/`: `SplashPage` waits for `AppUpdateCubit` and `BootstrapCubit`, then redirects to `/home`.
- `/home`: `HomePage` with the connect button, status and server info.
- `/update-required`: `UpdateRequiredPage`. The GoRouter `redirect` sends **every** route here while the update status is `required`; it listens to `AppUpdateCubit`, so a `426` from any API call switches the screen immediately.

These are the only three routes in v1.

## 5. State

- **`AppUpdateCubit`** (app_update feature) checks `GET /app/config` on start and on every `AppLifecycleState.resumed`. Without network it uses the cached policy. Its states are `unknown`, `upToDate`, `updateAvailable(policy)` and `updateRequired(policy)`. On `updateRequired` it asks `VpnBloc` to disconnect.
- **`BootstrapCubit`** (device feature) moves through `initial`, `registering`, then `registered` or `offline`. A failure does not block the home screen; registration is retried on connect.
- **`VpnBloc`** (vpn feature) handles the events `ConnectPressed`, `DisconnectPressed` and `EngineStatusChanged`. Its state is a `VpnStatus` union: `disconnected`, `preparing`, `permissionDenied`, `connecting`, `connected(since, tunnelIp, rx, tx)`, `disconnecting` and `failed(reason)`.
- **`ServerInfoCubit`** (servers feature) shows the cached server first, then refreshes it from `GET /servers`.

## 6. Local data

| Data | Storage |
| --- | --- |
| Device token, installation ID | `flutter_secure_storage` (Keychain, Android Keystore) |
| WireGuard private key | Native secure storage only; never passed to Dart |
| `user_id`, `device_id`, server list, last VPN config (public parts) | Drift tables `registration`, `servers`, `vpn_profile` |
| Last update policy (force upgrade) | Drift table `update_policy` |

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

- Requires a **paid** Apple Developer Program membership (free personal teams cannot use Network Extensions), the Network Extension capability (Packet Tunnel), an App Group and a shared Keychain access group.
- Team `RL5SKRM28G` is a paid individual membership (confirmed 2026-11-16); the organization enrollment is in progress. An individual paid membership is enough for development on the owner's devices and for Ad Hoc builds for family and friends. App Store release waits for the organization account.
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
