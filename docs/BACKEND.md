# خادم Generator OS (المزامنة، الأجهزة، التراخيص، لوحة المطور)

الخادم اختياري: التطبيق يعمل كاملاً بدونه. يلزم فقط لمزامنة عدة أجهزة (مثلاً هاتف المالك + أجهزة الجباة).

## التشغيل

```bash
cd server
dart pub get
export ADMIN_TOKEN="$(openssl rand -hex 24)"      # رمز لوحة الإدارة — احفظه بأمان
export LICENSE_SEED_B64="..."                     # اختياري: لإصدار التراخيص من الخادم
dart run bin/server.dart --port 8080 --db data/server.db
# أو ملف تنفيذي واحد:
dart compile exe bin/server.dart -o generator-os-server
```

ضعه خلف HTTPS (مثلاً Caddy أو Nginx مع Let's Encrypt). لا تشغّله على HTTP عبر الإنترنت.
قاعدة البيانات: ملف SQLite واحد (`data/server.db`) — خذ له نسخة احتياطية دورية.

## ربط جهاز

1. المطور ينشئ عميلاً (Tenant):
   ```bash
   curl -X POST https://SERVER/admin/tenants -H "authorization: Bearer $ADMIN_TOKEN" \
        -d '{"name":"مولدات الحي","share_status":true}'
   # => {"tenant_code":"T...","pairing_secret":"..."}
   ```
2. في التطبيق: **الإعدادات ← المزامنة ← ربط بخادم** وأدخل العنوان ورمز المؤسسة ورمز الربط.
3. اربط بنفس الرموز كل أجهزة نفس العميل. الجهاز الجديد يستلم كل البيانات (بما فيها حسابات المستخدمين).

## واجهة REST

| الطريقة | المسار | المصادقة | الوصف |
|---|---|---|---|
| GET | `/health` | — | فحص الحالة |
| POST | `/api/v1/pair` | رمز الربط | `{tenant_code, pairing_secret, device_id, device_name}` ← `{device_token}` |
| POST | `/api/v1/sync/push` | Bearer جهاز | `{device_id, changes:[{key, table, id, payload}]}` ← `{accepted:[key], conflicts:[…]}` |
| POST | `/api/v1/sync/pull` | Bearer جهاز | `{cursor, limit}` ← `{changes:[{seq, table, id, payload}], cursor, has_more}` |
| POST | `/api/v1/support` | Bearer جهاز | طلب دعم فني |
| GET | `/api/v1/releases/latest` | — | آخر إصدار للتطبيق |
| POST/GET | `/admin/tenants` | Bearer ADMIN_TOKEN | إدارة العملاء |
| GET | `/admin/devices` · POST `/admin/devices/<id>/revoke` | ADMIN | الأجهزة المفعلة وإبطالها |
| GET | `/admin/sync-status` | ADMIN | إحصاءات مزامنة (أعداد فقط) للعملاء الموافقين |
| POST/GET | `/admin/licenses` | ADMIN | إصدار وعرض التراخيص |
| POST | `/admin/releases` | ADMIN | نشر إصدار |
| GET | `/admin/support` | ADMIN | طلبات الدعم |

### الخصوصية

لوحة المطور **لا تحتوي أي واجهة تعرض السجلات المالية للعملاء**. حالة المزامنة أعداد إجمالية فقط، ولا تظهر إلا للعملاء الذين وافقوا (`share_status`). البيانات المخزنة على الخادم هي ما رفعه العميل نفسه للمزامنة؛ احمِ الخادم والقرص وفق ذلك.

### الضمانات

- **Idempotency**: كل تغيير له مفتاح؛ إعادة الإرسال بعد انقطاع لا تكرر أي دفعة.
- ترتيب التعارضات بتسلسل الخادم وليس بساعة الهاتف.
- السجل المالي المكرر بمحتوى مختلف يُرفض ويُسجل في `conflicts`.

## ملاحظة عن لوحة الإدارة

لوحة الإدارة حالياً **واجهة REST** (تُستخدم بـ curl أو Postman). واجهة ويب رسومية للوحة غير منفذة بعد — انظر FEATURES.md.
