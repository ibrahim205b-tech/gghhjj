import 'package:flutter/material.dart';

import '../app.dart';
import '../services/controller.dart';
import '../services/sound.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _server;
  late final TextEditingController _feed;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    _server = TextEditingController(text: s.serverUrl);
    _feed = TextEditingController(text: s.feedUrl);
  }

  @override
  void dispose() {
    _server.dispose();
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.settings;
    final r = s.rules;
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(t, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
        );
    Widget stepper(String label, int value, void Function(int) set, {int min = 0, int max = 999, int step = 1}) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(label, style: const TextStyle(fontSize: 14)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: value - step < min ? null : () => setState(() => set(value - step)),
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Display', fontSize: 18))),
            IconButton(
              onPressed: value + step > max ? null : () => setState(() => set(value + step)),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
        );

    return PopScope(
      onPopInvokedWithResult: (_, _) => c.saveSettings(),
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
          children: [
            section('الصوت'),
            Card(
              child: Column(children: [
                SwitchListTile(
                  key: const Key('mute'),
                  title: const Text('كتم الصوت'),
                  value: s.muted,
                  onChanged: (v) {
                    setState(() => s.muted = v);
                    c.saveSettings();
                  },
                ),
                ListTile(
                  title: const Text('مستوى الصوت'),
                  subtitle: Slider(
                    value: s.volume,
                    onChanged: s.muted ? null : (v) => setState(() => s.volume = v),
                    onChangeEnd: (_) {
                      c.saveSettings();
                      c.sound.play(Sfx.correct);
                    },
                  ),
                ),
                SwitchListTile(
                  title: const Text('عرض المقدمة السينمائية عند التشغيل'),
                  value: s.showIntro,
                  onChanged: (v) {
                    setState(() => s.showIntro = v);
                    c.saveSettings();
                  },
                ),
              ]),
            ),
            section('قواعد اللعب (للمنافسات الجديدة)'),
            Card(
              child: Column(children: [
                stepper('عدد الأخطاء قبل الإقصاء', r.strikeLimit, (v) => r.strikeLimit = v, min: 1, max: 10),
                stepper('وقت إجابة المزاد (ثانية)', r.auctionSeconds, (v) => r.auctionSeconds = v, min: 5, max: 180, step: 5),
                stepper('نقاط نجاح المزاد', r.auctionSuccessPoints, (v) => r.auctionSuccessPoints = v, step: 5),
                stepper('عقوبة فشل المزاد', r.auctionFailPenalty, (v) => r.auctionFailPenalty = v, step: 5),
                SwitchListTile(
                  title: const Text('خطأ (Strike) عند فشل المزاد', style: TextStyle(fontSize: 14)),
                  value: r.auctionStrikeOnFail,
                  onChanged: (v) => setState(() => r.auctionStrikeOnFail = v),
                ),
                stepper('نقاط «ماذا تعرف؟»', r.wdykPoints, (v) => r.wdykPoints = v, step: 5),
                stepper('وقت «ماذا تعرف؟» (ثانية)', r.wdykSeconds, (v) => r.wdykSeconds = v, min: 5, max: 120, step: 5),
                stepper('نقاط الجرس', r.buzzerPoints, (v) => r.buzzerPoints = v, step: 5),
                stepper('خصم الجرس عند الخطأ', r.buzzerWrongPenalty, (v) => r.buzzerWrongPenalty = v),
                stepper('العد التنازلي قبل الجرس', r.buzzerCountdown, (v) => r.buzzerCountdown = v, max: 10),
                stepper('وقت الإجابة بعد الجرس (ثانية)', r.buzzerAnswerSeconds, (v) => r.buzzerAnswerSeconds = v, min: 3, max: 60),
                for (var i = 0; i < r.whoAmIPoints.length; i++)
                  stepper('«من أنا؟» من التلميح ${i + 1}', r.whoAmIPoints[i], (v) => r.whoAmIPoints[i] = v, step: 5),
                SwitchListTile(
                  title: const Text('خطأ (Strike) عند تخمين خاطئ في «من أنا؟»', style: TextStyle(fontSize: 14)),
                  value: r.whoAmIStrikeOnWrong,
                  onChanged: (v) => setState(() => r.whoAmIStrikeOnWrong = v),
                ),
              ]),
            ),
            section('مصادر الأسئلة عبر الإنترنت'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text(
                    'خادم التوليد يولّد أسئلة جديدة عند الطلب ويتحقق منها. الموجز المنشور يُحدَّث دورياً عبر GitHub Actions. '
                    'لا يحتوي التطبيق على أي مفتاح API.',
                    style: TextStyle(color: C.muted, fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _server,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'رابط خادم التوليد (اختياري)', hintText: 'https://my-hhkkll-server.example.com'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _feed,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'رابط الموجز المنشور'),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    TextButton(
                      onPressed: () => setState(() => _feed.text = defaultFeedUrl),
                      child: const Text('الرابط الافتراضي'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        s.serverUrl = _server.text.trim();
                        s.feedUrl = _feed.text.trim();
                        await c.applySourceSettings();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المصادر')));
                        }
                      },
                      child: const Text('حفظ المصادر'),
                    ),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
