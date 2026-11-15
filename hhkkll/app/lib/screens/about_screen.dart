import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'intro_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('عن التطبيق')),
        body: StageBackground(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 20),
              const Center(child: Wordmark(size: 48)),
              const SizedBox(height: 8),
              const Center(
                child: Text('ULTIMATE FOOTBALL QUIZ · v1.0.0',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontFamily: 'Display', color: C.muted, letterSpacing: 3, fontSize: 11)),
              ),
              const SizedBox(height: 36),
              _card(Icons.workspace_premium_rounded, C.gold, introLine1),
              const SizedBox(height: 12),
              _card(Icons.code_rounded, C.cyan, introLine2),
              const SizedBox(height: 28),
              const Text('عن اللعبة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 8),
              const Text(
                'HHKKLL مسابقة كرة قدم بأسلوب البرامج التلفزيونية: أربعة أقسام (المزاد، ماذا تعرف؟، الجرس، من أنا؟)، '
                'وحكم يملك السيطرة الكاملة على النقاط والأخطاء والمؤقت.\n\n'
                'الأسئلة الجديدة تُولَّد عبر الإنترنت بالذكاء الاصطناعي، ولا تُقبل إلا بعد تحقق مستقل من مصادر فعلية، '
                'ولا يتكرر أي سؤال داخل الجلسة. حزمة البداية المدمجة مكتوبة يدوياً مع روابط مرجعية للحكم.',
                style: TextStyle(color: C.muted, height: 1.9),
              ),
            ],
          ),
        ),
      );

  Widget _card(IconData icon, Color col, String text) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: col.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: col.withValues(alpha: .4)),
        ),
        child: Row(children: [
          Icon(icon, color: col, size: 28),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: col))),
        ]),
      );
}
