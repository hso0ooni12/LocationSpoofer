# v63 Foreign Overlay Hider

## الهدف
منع ظهور فقاعات أدوات GPS الأخرى بجانب XsGpS مع إبقاء الأداة الأخرى فعّالة في الخلفية قدر الإمكان؛ الإخفاء يستهدف الواجهة فقط ولا يحاول تعطيل hooks أو منطق الأداة الأخرى.

## ما تم إضافته
- إضافة كشف خاص للفقاعة الدائرية الصغيرة التي تحمل النص `GPS` مثل الصورة المرسلة.
- الإخفاء لا يعتمد فقط على اسم الكلاس `k7gps`، بل يفحص:
  - `UILabel` / `UIButton` / `accessibilityLabel` / `accessibilityIdentifier` / `restorationIdentifier`.
  - النافذة ذات `windowLevel` مرتفع.
  - شكل الفقاعة الصغيرة الدائرية أو الـ compact control حتى لا يخفي شاشة التطبيق كاملة.
- حماية من false positives داخل عناصر التطبيق الطبيعية مثل:
  - `UITableViewCell`
  - `UICollectionViewCell`
  - `UINavigationBar`
  - `UITabBar`
  - `UIToolbar`
- إضافة hooks على:
  - `UIView setHidden:`
  - `UIView setAlpha:`

هذه hooks تمنع ظهور الفقاعة مرة ثانية إذا حاولت الأداة الأخرى إظهارها بعد ما نخفيها.

## ملفات معدلة
- `LSHooking.m`

## ملاحظة مهمة
الإخفاء intentionally لا يوقف الأداة الأخرى ولا يمنع dylib حقها من التحميل، فقط يخفي الواجهة المرئية حتى تبقى وظائفها الخلفية موجودة.
