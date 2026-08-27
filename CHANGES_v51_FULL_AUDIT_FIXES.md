# v51 - Full audit fixes after white-line root fix

## UI / Map picker
- Re-enabled the route/moving-location panel that existed in the codebase but was not being built.
- Added the route mode segment item in an older build; current UI is static-location only.
- Installed the route panel Auto Layout constraints that were previously never activated.
- Fixed route panel bottom constraints so route mode height is driven by the actual route controls instead of the static tools stack.
- Prevented `جلب المسار` from showing before both route endpoints are selected.
- Restored route simulation UI when an active simulation already exists.
- Kept vertical scrolling enabled so the lower tools do not get clipped on smaller screens or after map expansion/collapse.
- Kept the previous root-level white-line fix for the activation card: unified dark surfaces, removed the problematic top mask/corner, and kept the tiny same-color top fill.

## State / persistence
- Fixed a heading reset bug: when the old heading slider is not present in the compact UI, opening the screen no longer resets the saved heading to `0`.
- Guarded optional altitude/heading UI references so removed compact controls do not accidentally write stale/default values.
- Refreshed random-movement inline state immediately after toggling.

## Hooks / spoofing internals
- Fixed the alternative-image camera hook. The previous hook looked for `ls_captureOutput:didFinishProcessingPhoto:error:` on the wrong class, so the delegate hook could fail.
- Removed the unsafe NSObject category capture hook path that could recurse if invoked.
- Replaced it with a safer IMP hook that stores the original delegate implementation under a separate alias and calls it after attaching the spoofed image data.
- Fixed CLLocation delegate tracking so `locationManager:didUpdateLocations:` and the legacy `locationManager:didUpdateToLocation:fromLocation:` can both be hooked on the same delegate class instead of one blocking the other.

## Validation notes
- Performed a static pass for missing custom selectors and obvious dangling UI constraints.
- `make` cannot complete in this sandbox because Theos is not installed (`$(THEOS)/makefiles/common.mk` is missing). The project files were still reviewed and packaged after the source-level fixes.
