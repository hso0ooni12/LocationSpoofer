# v66 - Activation Flicker / Fast Presentation / Main Panel Animation

## Fixed

- Fixed the activation card flash where it briefly appeared, disappeared, then appeared again.
  - The card now starts hidden before the first render.
  - The entrance animation is played only once.
  - Repeated `viewDidAppear` calls no longer reset the card alpha/transform.

- Removed the activation prompt presentation delay/flicker caused by stacking a modal cross-dissolve over a second custom card animation.
  - The activation UI is now attached as a child overlay inside `MapPickerViewController`.
  - No fullscreen dim/blur layer is added by the activation UI.
  - The parent panel remains hidden while locked, so only the small activation card is visible.

- Made opening the tool feel faster.
  - The map picker is presented without UIKit's fullscreen transition delay.
  - The three-finger hold threshold was reduced from `0.8s` to `0.45s`.

## Improved

- Added the same smooth scale/fade entrance animation to the main XsGpS floating panel.
  - Initial opening now animates the main panel like the activation card.
  - After successful activation, the main tool panel appears with the same polished animation.

## Files changed

- `LSActivationViewController.h`
- `LSActivationViewController.m`
- `MapPickerViewController.m`
- `OverlayWindow.m`
