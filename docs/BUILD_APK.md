# بناء APK

## تلقائياً عبر GitHub Actions

الملف `.github/workflows/build.yml` يعمل عند كل push:

1. يثبت Flutter 3.47.9 و Java 17.
2. يفحص الكود (`analyze --fatal-infos`) ويشغّل اختبارات المحرك والخادم والتطبيق.
3. إذا نجحت الاختبارات يبني `flutter build apk --release`.
4. يحفظ الناتج باسم **`generator-os-release.apk`** كـ Artifact لمدة 30 يوماً، ويكتب ملخصاً بالحجم و SHA-256 ونوع التوقيع.

## التوقيع الآمن (Release)

لا توجد أي مفاتيح أو كلمات مرور داخل المستودع. لتفعيل التوقيع الرسمي:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks > keystore.b64
```

ثم في GitHub: **Settings ← Secrets and variables ← Actions** أضف:

| السر | القيمة |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | محتوى `keystore.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور المخزن |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح |
| `LICENSE_PUBKEY` | المفتاح العام للتراخيص (انظر LICENSING.md) — اختياري |

احتفظ بنسخة من ملف `.jks` وكلماته في مكان آمن؛ فقدانه يمنع تحديث التطبيق المثبت.

### الفرق بين النسختين

| | موقعة بمفتاح Debug (الافتراضي بدون أسرار) | موقعة بمفتاح Release |
|---|---|---|
| التثبيت والتجربة | ✔ | ✔ |
| النشر على Google Play | ✖ | ✔ |
| تحديث فوق نسخة سابقة | فقط فوق نسخ Debug من نفس جهاز البناء — مفتاح Debug في CI يتغير، لذا قد يلزم حذف التطبيق قبل التحديث (احفظ نسخة احتياطية أولاً!) | ✔ دائماً بنفس المفتاح |
| مناسبة للعملاء | للتجربة فقط | ✔ |

## محلياً

```bash
cd app
flutter pub get
flutter build apk --release --dart-define=LICENSE_PUBKEY=BASE64_KEY
# الناتج: build/app/outputs/flutter-apk/app-release.apk
```

للتوقيع المحلي أنشئ `app/android/key.properties` (مُستثنى من git):
```
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```
وضع `upload-keystore.jks` داخل `app/android/app/`.
