# v52 - UI, Bluetooth, Wi-Fi and hook stability audit

## UI / sheet sizing
- Increased the main tool sheet to use a near-full-height custom detent on iOS 16+ and a large-only detent on iOS 15.
- Increased Settings, Bookmarks, Schedule, Bluetooth, and Wi-Fi sheets to large-only presentation to reduce unnecessary scrolling.
- Enlarged the main map from a compact strip to a clearer near-square area.
- Increased expanded map height so the map zoom button gives a much more visible picker area.
- Enlarged the map expand button and the main status phrase such as "تغيير الموقع غير مفعل".

## Bluetooth fixes
- Sanitized discovered/saved Bluetooth device dictionaries before saving to NSUserDefaults.
- Sanitized loaded saved devices to remove old invalid records that can crash later.
- Added safe CBUUID parsing with exception guards for malformed UUID strings.
- Prevented broadcasting from dirty/incomplete saved Bluetooth records.
- Ensured pending Bluetooth broadcasts use the cleaned record, not the raw dictionary.
- Added guards for empty advertisement payloads before starting BLE advertising.

## Wi-Fi fixes
- Added multiple collection paths: MobileWiFi, CaptiveNetwork, NEHotspotNetwork, and currently active spoofed network.
- Sanitized saved networks before storing and before using them for active broadcast state.
- Saved active Wi-Fi broadcast data to both the shared suite defaults and standard defaults for better cross-process visibility.
- Kept the currently active broadcast visible in the scanner list even when no real scan results are returned.
- Improved no-result status messaging to mention permission/framework requirements and manual add fallback.

## Hooks / injection stability
- Removed unsafe global UIView hiding hook that matched "k7gps/k7" strings and could hide unrelated UI or collide with host apps.
- Made shared runtime hook installation idempotent so the same swizzle is not exchanged twice.
- Fixed dynamic CLLocation delegate hook selector names so the number of colons matches the original delegate selectors.
- Added an idempotency registry for CLLocation method exchanges.
- Added a fallback coordinate if stored spoofed location data is invalid.

## Validation
- Performed text-level Objective-C brace/interface balance checks on all .m files.
- Removed temporary backup files from the release archive.
