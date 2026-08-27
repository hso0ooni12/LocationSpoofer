# XsGpS v62 — Pre‑Launch Audit Fixes

هذه المراجعة ركزت على الأخطاء التي قد تظهر قبل الإطلاق في الـ hooks والأدوات الداخلية، مع تقليل الأعطال الصامتة ورفع جودة القيم التي تصل للتطبيقات.

## إصلاحات حرجة

### 1) ربط محاكي المسار بالـ CLLocation Hook
- كان محاكي المسار يحرّك واجهة الخريطة فقط بينما دالة إنشاء الموقع المزيف تقرأ آخر إحداثية محفوظة من `PersistenceManager`.
- تم تعديل `LSCreateSpoofedLocation()` ليقرأ مباشرة من `LSRouteSimulator` أثناء التشغيل أو الإيقاف المؤقت.
- تم تحديث `MapPickerViewController+Route` ليحفظ كل نقطة مسار جديدة في `PersistenceManager` أيضًا، كطبقة توافق إضافية.

### 2) تنظيف قيم CLLocation قبل إرسالها للتطبيق
- تم منع القيم غير الصالحة مثل `NaN` و `inf` في السرعة، الاتجاه، الارتفاع والدقة.
- تم ضبط الاتجاه داخل 0–360 درجة.
- تم منع دقة أفقية غير منطقية أقل من 3 أمتار.
- تم وضع fallback آمن إذا وصلت إحداثيات غير صالحة.

### 3) تحسين محاكي المسار
- تنظيف إحداثيات الـ polyline وتجاهل النقاط غير الصالحة.
- منع السرعات المخصصة السالبة أو غير المنطقية، مع حد آمن 1–300 كم/س.
- تشغيل Timer على الـ main run loop بطريقة آمنة.
- إرسال تحديثات الـ delegate من الـ main thread لتجنب مشاكل UI متقطعة.

## إصلاحات الأدوات

### Wi‑Fi Scanner / Spoofer
- إضافة تطبيع وتحقق كامل لـ BSSID.
- قبول الصيغ `aa:bb:cc:dd:ee:ff` و `aa-bb-cc-dd-ee-ff` و `aabbccddeeff`.
- رفض BSSID غير صالح بدل حفظه أو بثه بقيمة مكسورة.
- تحسين استجابة إذن الموقع بحيث لا يبدأ scan قبل انتهاء حالة `NotDetermined`.

### Bluetooth Spoofer
- نقل التخزين إلى suite ثابت `com.xsgps.dylib` مع fallback للـ standard defaults للتوافق مع الإصدارات السابقة.
- توحيد تحديثات الـ delegate على main thread.
- عدم اعتبار `startAdvertising` نجاحًا فوريًا؛ يتم الآن انتظار `peripheralManagerDidStartAdvertising:error:`.
- عرض رسالة خطأ حقيقية إذا فشل بث Bluetooth بدل إعطاء حالة نجاح وهمية.

### Image Spoofing
- كان hook الـ camera delegate يعتمد على فحص الكلاسات الموجودة وقت تحميل الأداة فقط.
- تم إضافة swizzle لـ `capturePhotoWithSettings:delegate:` حتى يتم hook أي delegate يُنشأ بعد تحميل الأداة.
- تم جعل hook الـ delegate قابلاً لإعادة الاستخدام بدون تكرار أو كراش.

## Build / Quality
- تم حذف `ADDITIONAL_CFLAGS = -w` من `Makefile` حتى لا تُخفى التحذيرات المهمة قبل الإطلاق.
- أبقيت `-Wall -Wextra -Wno-error` حتى تظهر التحذيرات بدون كسر البناء فورًا.

## ملاحظات إطلاق مهمة

- لم يتم تنفيذ build فعلي داخل هذه البيئة لأن Theos غير متوفر هنا (`$(THEOS)/makefiles/common.mk` غير موجود).
- لازم تشغيل build فعلي على بيئة Theos/iOS SDK قبل الإطلاق.
- يفضل اختبار النسخة على جهاز حقيقي وعلى أكثر من إصدار iOS.
- نظام التفعيل الحالي يعتمد على توكن محلي مشتق من secret داخل التطبيق؛ الأفضل أمنيًا في إصدار إنتاجي استخدام تحقق موقّع من السيرفر بمفتاح عام داخل التطبيق بدل secret ثابت داخل الكود.
- أي ميزة تجمع أو ترسل معلومات جهاز يجب أن تكون واضحة للمستخدم ومتوافقة مع سياسة الخصوصية الخاصة بك.

## الملفات المعدلة

- `XsGpS.m`
- `RouteSimulator.m`
- `MapPickerViewController+Route.m`
- `LSWiFiScannerViewController.m`
- `LSWiFiNetworkSpoofer.m`
- `BluetoothSpooferManager.m`
- `ImageSpoofingManager.m`
- `Makefile`
