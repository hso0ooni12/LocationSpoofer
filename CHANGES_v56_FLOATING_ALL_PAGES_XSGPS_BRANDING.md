# v56 - Floating Subpages + XsGpS Branding

## Floating UI

- Added a shared floating panel helper (`LSFloatingPanel.h/.m`) so tool pages use one consistent floating style.
- Converted these pages to floating panels with visible margins, rounded corners, border, grabber, dimmed background, and soft shadow:
  - Schedule editor page.
  - Bluetooth scanner page.
  - WiFi scanner page.
  - Saved bookmarks page.
  - Settings page.
  - Reference image settings page.
  - Inline alternative-image preview page.
- Replaced page-sheet/full-screen presentations with `UIModalPresentationOverFullScreen` where needed, so the floating boundaries stay visible on all pages.
- Removed old sheet-detent setup from the converted pages to prevent them from expanding as native full-screen sheets.

## Branding

- Renamed the build product/library from the previous product name to `XsGpS`.
- Renamed the main hook owner class/files from the previous product name to `XsGpS` while keeping the existing exported LS hook functions for compatibility.
- Updated the dylib install name to `XsGpS.dylib`.
- Updated GitHub artifact naming to `XsGpS-dylib`.
- Updated internal defaults/log namespaces from the old namespace to `com.xsgps.*`.
- Updated visible project documentation/header references to `XsGpS`.
- Updated the k7gps hider own-tool whitelist to recognize `xsgps` so it does not hide this tool’s own UI.

## Notes

- Internal feature class names such as WiFi/Bluetooth managers were left intact unless they represented the official product/library name, to avoid unnecessary compatibility risk.
- A real device/Theos build was not run in this sandbox because iOS SDK/Theos are unavailable here.
