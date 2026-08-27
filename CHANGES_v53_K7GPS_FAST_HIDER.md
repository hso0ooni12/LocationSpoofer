# v53 - Fast k7gps UI Hider Restore

## Restored hook
- Restored the k7gps UI hiding hook that was removed during the previous cleanup.
- Rebuilt it as a narrow, safer hook that targets only k7gps-like UI signatures instead of the broad `k7` match.

## Speed improvements
- Added `willMoveToWindow:` hook to hide matching views before they appear on screen.
- Kept `didMoveToWindow` hook as a fallback for views that are assembled after being attached.
- Added short launch/foreground burst scans only; no permanent repeating timer.
- Added class-name positive/negative caches to reduce repeated string matching.

## Stability improvements
- Avoids hiding `UIWindow` and avoids hiding huge/root containers.
- Hides compact parent wrappers for text-based k7gps labels so empty panels are less likely to remain visible.
- Keeps the other tweak active in the background by hiding UI only: `hidden`, `alpha`, `userInteractionEnabled`, and accessibility visibility.
- Uses the existing guarded `LSInstallInstanceHookWithIMP` helper to avoid duplicate swizzles.
- Also matches class/identifier/text names where `k7` and `gps` appear separated, while still avoiding the old broad `k7`-only match.
