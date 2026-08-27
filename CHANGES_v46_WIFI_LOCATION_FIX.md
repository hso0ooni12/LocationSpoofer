# v46 - Wi-Fi Button + Real Location Fix

- Added a new `الوايفاي` button directly under the Bluetooth button on the main tool screen.
- Added `LSWiFiScannerViewController` with a Bluetooth-style sheet: radar view, scan/update button, discovered/saved tabs, save, activate/deactivate, delete, and copy network data.
- Wi-Fi discovery uses MobileWiFi when available and falls back to the current Wi-Fi network via CaptiveNetwork.
- Fixed `موقعي` so it temporarily bypasses the location spoofing hook and requests the device's real CoreLocation coordinate before moving the map pin.
- Reduced the visual top-line glitch above the `تفعيل تغيير الموقع` card by removing spacing/border bleed from the top action row.
