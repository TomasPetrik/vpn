# 0007: Force upgrade controlled from the admin panel

Status: Accepted (2026-11-16)

## Context

The first users are family and friends, with the app installed from test channels (Ad Hoc / TestFlight on iOS, a Google Play testing track on Android). When the API, the transport or a security fix changes, old builds must be stopped. The owner wants to set this in the admin panel.

## Decision

- **Version identity:** the integer **build number** (`version: x.y.z+BUILD` in `pubspec.yaml`, which becomes `versionCode` on Android and `CFBundleVersion` on iOS). It only ever increases. The version name (`x.y.z`) is shown to people only.
- **Policy per platform**, edited at `/admin/app-versions`:
  - `min_supported_build`: builds below it are **blocked** (force upgrade).
  - `latest_build`: builds below it get a dismissible "update available" prompt.
  - `update_url`: where the update button leads (Play testing link, TestFlight link or a download page).
  - `message` (optional): text shown to the user; the app has a default text.
  - Before saving, the panel shows how many devices the change would block, based on each device's last reported build.
- **App side:**
  - Calls `GET /api/v1/app/config` on every start and every return to the foreground. No authentication is needed, so it works even before registration.
  - Sends `X-App-Platform`, `X-App-Build` and `X-App-Version` on every API request.
  - When an update is required, it disconnects the VPN and shows a full-screen blocking page with an update button. Nothing else in the app is reachable.
  - Keeps the last policy in Drift, so an outdated build stays blocked even when it starts offline.
- **Backend side:**
  - Every API request (except `/app/config` and `/healthz`) from a build below the minimum gets `426` with code `app_update_required`. The app shows the blocking page even if it missed the regular check.
  - Stores the last reported build per device, so the admin panel shows who runs which version.
- **Tunnel:** not enforced at the tunnel level in v1. WireGuard cannot see the app version, so an already running tunnel keeps working until the app is opened again. Later option: a "revoke peers of blocked devices" button.
- **The mechanism must be in the very first build given to anyone.** Builds without it can never be forced.

## Consequences

- One small write form in the otherwise read-only admin panel, protected by CSRF and a confirmation step.
- Works the same for every distribution channel, including test builds outside the stores.

## Alternatives considered

- **Firebase Remote Config:** adds an external service and SDK for a single value.
- **Play in-app updates (`in_app_update`):** Android and Play only; does not cover iOS or test builds. It can be added later as a nicer Android flow on top of this mechanism.
