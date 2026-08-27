# XsGpS

Clean ready build package for the iOS dylib.

## Structure
- ملفات `.m/.h` في جذر المشروع هي المصدر الأساسي.
- `Makefile` يبني من ملفات الجذر أولاً، ويستخدم `Source/*.m` فقط كخطة احتياطية.
- `.github/workflows/main.yml` can build the project with Theos on GitHub Actions.

## Build
Upload the contents of this folder to the repository root, then run the GitHub workflow manually.

## V45 UUID effective apply
- `Makefile` now builds from root `*.m` first, otherwise from `Source/*.m`, so UUID fixes are not skipped by an empty Source folder.
- The GitHub workflow deletes stale `Source/` and copies the current root `.m/.h` files before building.
- `LSUUIDResetManager` centralizes UUID restart cleanup for both the main inline button and the UUID manager screen.
- The restart cleanup preserves `com.xsgps` state, then clears host Documents, Library data, tmp, cookies, WebKit storage, URL cache, and the host app Keychain.

Server-side account/device binding can still require more than UUID/local data cleanup.
