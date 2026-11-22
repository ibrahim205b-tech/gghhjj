# واجهات API

التوثيق التفاعلي الكامل (Swagger/OpenAPI) متاح على الخادم نفسه: `GET /docs` و `GET /openapi.json`.
كل مسارات `/api/*` تتطلب الترويسة `Authorization: Bearer <SAWTI_API_KEY>` (أو `X-API-Key`).
الأخطاء بصيغة موحدة: `{"detail": {"code": "...", "message": "رسالة عربية"}}`.

| الطريقة | المسار | الوظيفة | أهم الردود |
|---|---|---|---|
| GET | `/health` | فحص الصحة (عام) وحالة المحرك `not_loaded/loading/ready/failed` | 200 |
| GET | `/api/status` | معلومات المحرك (الاسم، الترخيص، اللغات، متطلبات العينة، السرعة، الأنماط، الجودة)، الحدود، الطابور | 200، 401 |
| POST | `/api/engine/load` | بدء تحميل المحرك إن لم يكن محملاً | 200 |
| POST | `/api/voice/upload` | multipart: `file` (WAV/MP3/M4A…)، `name`، `transcript` ← فحص الصيغة الحقيقية والحجم والمدة، تحويل، تقرير جودة | 201، 400 فارغ، 413 كبير، 415 غير مدعوم، 422 قصير/طويل/بلا كلام |
| POST | `/api/voice/prepare` | `{"voice_id"}` ← عملية تجهيز غير متزامنة، يعيد `job_id` | 202، 404، 503 المحرك يُحمّل، 429 الطابور ممتلئ |
| GET | `/api/voice/status?voice_id=` | حالة النسخة: `uploaded/preparing/ready/failed` | 200، 404 |
| GET | `/api/voices` | قائمة النسخ على الخادم | 200 |
| DELETE | `/api/voice?voice_id=` أو `/api/voice/{id}` | حذف النسخة وعينتها ومرجعها | 200، 404 |
| DELETE | `/api/voice/{id}/original` | حذف العينة الأصلية فقط (يبقى المقطع المرجعي اللازم للتوليد) | 200، 404 |
| POST | `/api/tts/generate` | `{"voice_id","text","language","speed","style","quality","request_id"}` ← عملية توليد | 202، 404، 409 غير جاهزة، 413 نص طويل، 422 نص فارغ |
| GET | `/api/tts/status?job_id=` أو `/api/tts/status/{job_id}` | الحالة: `queued/running/done/failed`، التقدم، الأجزاء، الخطأ، النتيجة (`audio_id`, المدة، الحجم) | 200، 404 |
| GET | `/api/audio/{id}?format=wav|mp3|m4a` | تنزيل الملف (محمي بالمفتاح، مؤقت) | 200، 401، 404 منتهي/محذوف |
| GET | `/api/audio/{id}/info` | الحجم والمدة قبل التنزيل | 200، 404 |
| DELETE | `/api/audio/{id}` | حذف ملف ناتج | 200، 404 |
| DELETE | `/api/data` | حذف كل البيانات (النسخ، العينات، الملفات) | 200 |

## ملاحظات
- `request_id`: معرّف فريد من التطبيق؛ تكرار الطلب نفسه يعيد نفس العملية (يمنع التوليد المكرر بالخطأ).
- عملية واحدة تعمل في وقت واحد (CPU)؛ البقية في طابور بحد أقصى `SAWTI_MAX_QUEUE`.
- `speed` يُطبَّق فقط إذا كان المحرك يدعمه (SILMA: 0.7–1.3). `style` يُطبَّق مع Chatterbox فقط. `quality` مع SILMA فقط
  (`fast/balanced/high` = خطوات انتشار 12/16/32).
- معدل الطلبات: 60/دقيقة لكل عميل؛ 10 محاولات مفتاح خاطئ/دقيقة ثم 429.
