# XsGpS v59 — License Device Info

## Added
- Activation requests now send safe device metadata to the license server:
  - device_name
  - device_udid
  - ios_version
  - system_name
  - device_model
  - app_version when available
- UDID lookup tries MobileGestalt first on jailbroken devices and falls back to the active device/app identifier when the real value is unavailable.
- Already activated users sync their device info quietly through `/verify` at most once every 6 hours when the tweak loads.
- The license payload remains backward compatible with the existing server fields:
  - code
  - device_id

## Server pairing
- Use `worker-xsgps-v59-device-info.js` with this app build.
- The worker auto-migrates the D1 table by adding the new columns if they are missing.
- Existing activation codes remain valid.
