# XsGpS v60 — Build duplicate symbol fix

Fixed a linker error caused by compiling both the old legacy main hook file `LocationSpoofer.m` and the renamed official main hook file `XsGpS.m`.

## What changed

- Updated `Makefile` to automatically exclude `LocationSpoofer.m` when `XsGpS.m` exists.
- Updated GitHub Actions prepare step to remove legacy duplicate hook files after moving sources into `Source/`.
- This fixes duplicate symbols:
  - `_LSIsInternalLocationCreate`
  - `_LSCreateSpoofedLocation`
  - `_LSSetHooksBypassed`

No license-server endpoints or activation payload names were changed.
