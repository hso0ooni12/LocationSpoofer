V40 Build Repair

This version fixes the exact LSToolsCenterViewController errors shown in the GitHub log:
- ARC write-back errors from addresses of ivars
- missing LSSetHooksBypassed declaration
- invalid iOS 16 custom detent identifier

The workflow now deletes the old Source directory at the beginning of every run and copies the root .m/.h files again. This prevents stale source files from earlier uploads from being compiled.

Upload the CONTENTS of this folder to the repository root. Do not upload the outer folder itself.
