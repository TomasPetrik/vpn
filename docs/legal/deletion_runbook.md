# PetrikVPN device data deletion runbook

**Contact inbox:** `info@petrixon.com`  
**SLA:** reply and complete within **30 days** of a verifiable request.

## What to delete / anonymize

For the matched device (and its anonymous user row if no other devices remain):

1. `device_diagnostics` rows for `device_id` (cascade also deletes on device delete).
2. `wireguard_peers` for the device (cascade from devices, plus remove live `wg1` peer via admin/API if still present).
3. `devices` row (installation id, hashed identifier, token hash, last_client_ip/country, app metadata).
4. `users` row if that user has **no remaining devices**.
5. Confirm peer is gone from kernel (`wg show wg1`) after next reconcile / manual remove.

Do **not** keep browsing/DNS/content logs — they are not collected. Peer_stats_samples cascade with the peer.

## How to locate the record

From the email, use any of:

- Installation ID (Settings → Request data deletion pre-fills this)
- Platform + model + approximate registration time
- Device ID / user ID if the user pasted a diagnostic or support mail

Admin: `/admin/devices` → search by id / model / installation id (SQL if needed).

```sql
SELECT id, user_id, platform, model, installation_id, created_at
FROM devices
WHERE installation_id = ?
   OR id = ?
   OR model LIKE ?
ORDER BY created_at DESC;
```

## Verification before delete

Ask for one extra confirming detail only if multiple candidates match (e.g. platform + model). Do not require creating an account.

## Reply template

> We deleted (or irreversibly anonymized) the PetrikVPN device registration and related peer/diagnostic records associated with your request. If you still have the app installed, uninstalling removes local on-device data as well.
