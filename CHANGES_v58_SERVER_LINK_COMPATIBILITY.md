# XsGpS v58 - Server Link Compatibility

- ثبّت رابط سيرفر التفعيل داخل الأداة على الرابط العامل السابق:
  `https://location-spoofer-api.hso0ooni14.workers.dev`
- بقيت endpoints كما هي بدون تغيير:
  - `POST /activate`
  - `POST /verify`
- بقي payload المرسل من الأداة كما هو:
  - `code`
  - `device_id`
- بقيت صيغة الرد المعتمدة من الأداة كما هي:
  - `ok`
  - `message`
- أضيفت قراءة/ترحيل تلقائي من تخزين النسخ القديمة:
  - `com.locationspoofer.dylib`
  - `com.locationspoofer.activation.plist`
  - `com.locationspoofer.uuid.plist`
- الهدف من الترحيل هو منع فقدان التفعيل المحلي أو تغيّر بيانات UUID بعد تغيير الاسم الرسمي إلى `XsGpS`.
- Worker v58 يعيد الآن `expires_at` و `duration_days` في ردود التفعيل والتحقق حتى تظهر مدة الاشتراك داخل الأداة عند توفرها.
