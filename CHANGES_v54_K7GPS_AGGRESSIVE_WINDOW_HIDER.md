# v54 - Aggressive k7gps Window/UI Hider

## Why this update was made
- v53 only matched full `k7gps`-style names. The screenshot showed the other tweak UI was still visible, which usually means its visible overlay is using a short `k7` class/module name or a dedicated `UIWindow`/root controller without the full `k7gps` text.

## What changed
- Restored the effective broad `k7` class/identifier match from the older hook, but kept it safer by applying broad matching only to class names, accessibility identifiers, restoration identifiers, and view-controller names.
- Kept visible label/button text matching narrow: user-visible text must still contain `k7gps` or `k7` + `gps` together.
- Added dedicated `UIWindow` detection:
  - hides windows whose class/root view controller looks like `k7gps`/`k7`.
  - hides elevated overlay windows entirely when a k7 target is found inside them.
- Added `didAddSubview:` hook so late-added k7gps panels get hidden after insertion.
- Kept `willMoveToWindow:` and `didMoveToWindow` hooks for early hiding before/after attach.
- Added `makeKeyAndVisible` hook for new overlay windows.
- Added observers for visible/key window notifications and app launch/active notifications.
- Increased launch burst scan timing up to 3 seconds without leaving a permanent repeating timer.

## Safety notes
- The hider skips this project’s own UI classes such as XsGpS, LSOverlay, MapPicker, WiFi, Bluetooth, Bookmarks, Schedule, and Activation screens.
- Direct root hiding of the normal app window is avoided unless the root view is a compact overlay-sized panel. Elevated tweak windows can be fully hidden.

## Build note
- The sandbox does not include Theos/iOS SDK, so a full device build was not executed here.
- Source structure and bracket balance were checked after the patch.
