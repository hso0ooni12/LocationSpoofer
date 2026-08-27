# v38 build fix

- Fixed `LSScheduleManager.h`: removed stray `+` characters from the continuation lines of the `saveWithStartDate:endDate:recurrence:weekdays:` method declaration.
- This restores the selector declaration used by `LSScheduleEditorViewController`.
