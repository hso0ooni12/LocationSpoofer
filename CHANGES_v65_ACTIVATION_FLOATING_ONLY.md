# CHANGES v65 — Activation Floating Window Only

Requested fix: the activation prompt must be a small activation window only, without a full-screen dark/blur background and without showing the locked XsGpS panel behind it.

## What changed

- Removed the full-screen dim/blur layer from `LSActivationViewController`.
- Kept only the compact dark activation card visible.
- Reduced the card size and spacing so it feels like a popup, not a near-full-screen panel.
- Stopped auto-opening the keyboard on presentation; the keyboard appears only after the user taps the code field.
- Changed the activation modal presentation to `UIModalPresentationOverCurrentContext`.
- Added a locked presentation mode in `MapPickerViewController`:
  - hides the large XsGpS floating panel while activation is required,
  - clears the host background while locked,
  - restores the normal XsGpS panel immediately after successful activation.
- Kept the cancel behavior: pressing `إلغاء` closes the activation prompt and dismisses the tool cleanly.

## Files changed

- `LSActivationViewController.m`
- `MapPickerViewController.m`
