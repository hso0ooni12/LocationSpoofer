# v36 build fix

- Fixed `ImageSpoofingManager` compilation on Theos/legacy Objective-C runtime by explicitly declaring the `_referenceEnabled` backing instance variable in the primary interface.
- No change to the reference-image behavior.
