# XsGpS v69 – Activation child overlay dismissal fix

## المشكلة التي تم إصلاحها
بعد إدخال كود التفعيل والضغط على **تفعيل** كانت نافذة التفعيل تختفي، ثم تظهر شاشة الأداة الرئيسية للحظة قصيرة، وبعد أقل من ثانية تختفي شاشة الأداة بالكامل.

## السبب الحقيقي
`LSActivationViewController` صار يُعرض كـ child overlay داخل `MapPickerViewController`، لكن كود النجاح كان ما زال يستخدم:

```objc
[self dismissViewControllerAnimated:NO completion:successBlock];
```

في بعض حالات UIKit، `presentingViewController` يكون موجودًا حتى للـ child controller بسبب أن الأب نفسه معروض كـ modal. لذلك استدعاء `dismissViewControllerAnimated:` من شاشة التفعيل كان يغلق الـ modal الأب، أي يغلق شاشة XsGpS الرئيسية بعد ظهورها مباشرة.

## الإصلاح
تم تعديل `LSActivationViewController.m` بحيث:

- إذا كانت شاشة التفعيل مضافة كـ child داخل شاشة الأداة، لا يتم استدعاء `dismissViewControllerAnimated:` نهائيًا.
- يتم تشغيل `successBlock` فقط، و `MapPickerViewController` هو الذي يزيل نافذة التفعيل من داخل نفسه.
- لا يتم استخدام UIKit dismissal إلا إذا كانت شاشة التفعيل نفسها هي الـ presented view controller مباشرة.
- نفس الحماية أُضيفت لمسار زر الإلغاء حتى لا يحصل dismiss مزدوج أو إغلاق غير مقصود.

## النتيجة المتوقعة
بعد نجاح التفعيل:

1. تختفي نافذة التفعيل.
2. تظهر شاشة الأداة الرئيسية.
3. تبقى شاشة الأداة ظاهرة ولا تختفي بعد أقل من ثانية.
