# XsGpS v70 — Real Location / موقعي Fix

## المشكلة
أحياناً عند الضغط على خيار **موقعي** كان يظهر خطأ أو يفشل تحديد الموقع الحقيقي.

## السبب المحتمل
- `CLLocationManager` قد يرجع `kCLErrorLocationUnknown` بشكل مؤقت في بداية الطلب، والكود السابق كان يعتبره فشل نهائي مباشرة.
- الأداة تعمل داخل تطبيقات مختلفة، وبعض التطبيقات المضيفة لا تحتوي مفاتيح صلاحية الموقع داخل `Info.plist` مثل `NSLocationWhenInUseUsageDescription`. طلب الصلاحية داخل هذه التطبيقات قد يسبب خطأ أو crash من iOS.
- كان يتم تشغيل `showsUserLocation` في `MKMapView` بدون فحص أمان صلاحية الموقع للتطبيق المضيف.
- عند تغيّر الصلاحية قد يتم إرسال طلبات location متكررة فوق بعضها.

## الإصلاحات
- إضافة فحص آمن قبل طلب الموقع الحقيقي أو تفعيل `showsUserLocation`.
- منع طلب صلاحية الموقع داخل أي تطبيق لا يحتوي Location Usage Description.
- تجاهل `kCLErrorLocationUnknown` المؤقت وعدم إنهاء العملية فوراً.
- إضافة مهلة 10 ثواني مع fallback من آخر قراءة حقيقية متاحة.
- اختيار أفضل موقع من `didUpdateLocations` بدل أخذ آخر عنصر فقط.
- منع الضغط المتكرر على زر **موقعي** أثناء البحث.
- استخدام generation token لمنع callbacks القديمة من التأثير على طلب جديد.
- إرجاع حالة hook spoofing بعد انتهاء البحث أو فشله.

## الملفات المعدلة
- `MapPickerViewController.m`
- `MapPickerViewController+Core.m`
- `MapPickerViewController+Private.h`
