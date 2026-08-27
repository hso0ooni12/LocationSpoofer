# v64 - Activation UI Redesign

- Redesigned `LSActivationViewController` to match the requested simple dark activation card.
- Added blurred/dimmed background, rounded dark card, right-aligned Arabic labels, large pill input, and two horizontal buttons: `إلغاء` and `تفعيل`.
- Added automatic uppercase/clean code normalization while typing.
- Added dark keyboard appearance and one-time-code text content type.
- Added loading spinner inside the activation button while checking the code.
- Added inline error display and a light shake animation for invalid activation attempts.
- Added keyboard-aware vertical adjustment so the card does not feel cramped while typing.
- Added `onCancel` callback so pressing `إلغاء` closes the activation prompt cleanly without leaving the hidden tool UI stuck behind it.
