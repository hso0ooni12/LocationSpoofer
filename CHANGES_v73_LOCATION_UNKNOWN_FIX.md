# XsGpS v73 — kCLErrorDomain error 0 Fix

## المشكلة
أحياناً عند الضغط على **موقعي** يظهر النص الخام:

`The operation couldn't be completed. (kCLErrorDomain error 0.)`

هذا الخطأ هو `kCLErrorLocationUnknown` (code 0)، وهو خطأ مؤقت من CoreLocation يعني أن النظام لم يحصل على fix مناسب في تلك اللحظة، وليس رفض صلاحية نهائي.

## التعديل
- عدم حفظ `kCLErrorLocationUnknown` كخطأ نهائي أو عرضه للمستخدم.
- الاستمرار في `startUpdatingLocation` وانتظار fix جديد بدلاً من الجمع معه `requestLocation` one-shot.
- محاولة استخدام cached location مرة أخرى عند وصول code 0.
- رفع مهلة البحث من 4 ثوانٍ إلى 8 ثوانٍ لتحسين النجاح داخل المباني أو عند بداية تشغيل خدمات الموقع.
- عدم عرض `localizedDescription` الخام في واجهة المستخدم عند انتهاء المهلة.

## الملف المعدل
- `MapPickerViewController.m`
