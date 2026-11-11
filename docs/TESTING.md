# الاختبارات

كل الاختبارات تستخدم قواعد بيانات SQLite **في الذاكرة** تُنشأ وتُحذف مع كل اختبار — منفصلة تماماً عن أي بيانات عملاء.

```bash
cd packages/generator_core && dart test   # 34 اختباراً: المحرك
cd server && dart test                    # 6 اختبارات: خادم حقيقي + جهازان
cd app && flutter test                    # 7 اختبارات: الواجهة والطباعة والتصدير
```

## مطابقة قائمة الاختبارات المطلوبة

| # | الاختبار | أين | الحالة |
|---|---|---|---|
| 1 | إنشاء مولدة (مع دليل الحسابات والصندوق) | core `creates generator…` | ✅ |
| 2 | إنشاء منطقة | core `creates generator…` | ✅ |
| 3 | إنشاء كابينة | core `creates generator…` | ✅ |
| 4 | إضافة مشترك | core `adds subscriber…` | ✅ |
| 5 | إنشاء فاتورة | core `monthly generation…` | ✅ |
| 6 | دفعة كاملة | core `full payment…` | ✅ |
| 7 | دفعة جزئية | core `partial payment…` | ✅ |
| 8 | ترحيل الدين | core `partial payment… debt carries` | ✅ |
| 9 | عدم تكرار الفاتورة | core `second invoice… refused` + server `same month billed offline on two devices` | ✅ |
| 10 | تسجيل مصروف | core `expense on credit…`, `daily close…` | ✅ |
| 11 | شراء كاز | core `purchase, weighted-average…` | ✅ |
| 12 | استهلاك كاز | core `purchase, weighted-average…` | ✅ |
| 13 | إغلاق الصندوق | core `daily close…` | ✅ |
| 14 | مطابقة حساب الجابي | core `collector custody, handover and reconciliation` | ✅ |
| 15 | انقطاع الإنترنت | server `network failure keeps changes queued…` | ✅ |
| 16 | دفعة دون إنترنت | server `two devices: offline payments…` | ✅ |
| 17 | عودة الإنترنت والمزامنة | server `two devices…`, `network failure…` | ✅ |
| 18 | منع تكرار العملية | core `same request id…` + server replay | ✅ |
| 19 | صلاحيات الجابي | core `collector sees only assigned…` + app `collector sees collection only` | ✅ |
| 20 | صلاحيات المالك | core `owner has every permission…` | ✅ |
| 21 | استعادة نسخة احتياطية | core `encrypted backup restores…` | ✅ |
| 22 | إنشاء PDF | app `Arabic receipt and report PDFs` | ✅ |
| 23 | تصدير Excel | app `Excel export contains Arabic…` | ✅ |
| 24 | واجهات الهاتف والتابلت | app `phone: dashboard…`, `tablet landscape…`, `every module screen opens…` | ✅ (اختبارات واجهة آلية بأحجام شاشات مختلفة) |
| 25 | الطباعة على طابعة فعلية | — | ⏳ **لم يُنفذ**: لا تتوفر طابعة في بيئة التطوير. اختبار ترميز ESC/POS آلي فقط ✅ |

## اختبارات إضافية

- القيود غير المتوازنة مرفوضة؛ دفتر الأستاذ متوازن بعد كل سيناريو.
- الحذف/التعديل المباشر للسجلات المالية وسجل التدقيق مرفوض على مستوى قاعدة البيانات.
- إلغاء الدفعة بقيد عكسي مرة واحدة فقط.
- استهلاك كامل المخزون لا يترك فروقات تقريب.
- كشف الاستهلاك غير الطبيعي، توقع الوقود.
- نقل مشترك لمولدة أخرى يحفظ الدين في المولدة الأصلية.
- الإعفاء، تعديل الفاتورة الموثق، إغلاق الشهر.
- القفل بعد محاولات الدخول الفاشلة، إبطال الجلسة، سجل التدقيق.
- حد الترخيص وعدم قفل البيانات، التحقق من توقيع الترخيص ورفض المزور والجهاز الآخر.
- تعارض تعديلين متزامنين يُحسم بترتيب الخادم، وإبطال الجهاز يوقف مزامنته.
- أسئلة المساعد بالعربية واللهجة العراقية بأرقام حقيقية.

## أخطاء حقيقية كشفتها الاختبارات وتم إصلاحها

1. أرقام الوصولات من جهازين كانت تتطابق فتفشل مزامنة الدفعة الثانية (اختبار المزامنة الشامل).
2. فلتر «عليهم ديون» استخدم `HAVING` بدون `GROUP BY` فرفضته SQLite (اختبار الواجهة).
3. خط Naskh العربي لا يحتوي حروفاً لاتينية فكانت أرقام الوصل تختفي من PDF — أُضيف خط Noto Sans احتياطياً.
4. قائمة منسدلة تتجاوز عرض الشاشة في التقارير.

## يتطلب تحققاً يدوياً على أجهزة حقيقية

- تثبيت APK وتشغيله على هاتف وتابلت أندرويد فعليين.
- الطباعة على طابعة حرارية (شبكية/Bluetooth) وطابعة عادية.
- الأداء مع آلاف المشتركين على هاتف متوسط.
