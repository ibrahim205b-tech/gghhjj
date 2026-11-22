import 'package:flutter/material.dart';

import '../widgets/common.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    ('تطبيق شخصي', 'صوتي AI مخصص لاستنساخ صوتك أنت فقط. لا تستخدمه لاستنساخ صوت أي شخص دون موافقته الصريحة.'),
    ('أين تُحفظ بياناتك؟',
        'العينة الصوتية والملفات المولدة تُحفظ في التخزين الخاص بالتطبيق على هاتفك، ولا تصل إليها التطبيقات الأخرى. '
            'لا تُرفع أي ملفات إلى GitHub ولا تُضمَّن في ملف التطبيق.'),
    ('ماذا يُرسل إلى الخادم؟',
        'تُرسل العينة والنص الذي تكتبه إلى خادمك الخاص فقط عبر اتصال مشفر (HTTPS) ومحمي بمفتاح وصول لا يعرفه غيرك. '
            'يحتفظ الخادم بالمقطع المرجعي اللازم للتوليد، وتُحذف الملفات المولدة بعد تنزيلها أو بعد انتهاء صلاحيتها.'),
    ('السجلات', 'لا يسجل الخادم النصوص ولا الأصوات. تُسجل فقط معلومات تشغيلية مثل مدة المعالجة وعدد الأحرف.'),
    ('الاستضافة المجانية',
        'إذا استخدمت مساحة Hugging Face مجانية، فإن الكود عام لكن البيانات ليست كذلك: كل الطلبات تتطلب مفتاحك، '
            'والتخزين مؤقت ويُمسح عند إعادة تشغيل الخادم.'),
    ('التحكم الكامل',
        'من الإعدادات يمكنك حذف العينة الأصلية من الخادم، أو حذف النسخة الصوتية من الخادم والجهاز، أو حذف جميع ملفاتك المحلية، '
            'أو حذف كل بياناتك من الخادم بضغطة واحدة.'),
    ('العلامة المائية', 'بعض المحركات (مثل Chatterbox) تضيف علامة مائية غير مسموعة تدل على أن الصوت مولد بالذكاء الاصطناعي.'),
  ];

  @override
  Widget build(BuildContext context) => SawtiScaffold(
        title: 'سياسة الخصوصية',
        body: ListView(padding: const EdgeInsets.all(20), children: [
          for (final (t, b) in _sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(b, style: const TextStyle(height: 1.7)),
                ]),
              ),
            ),
        ]),
      );
}
