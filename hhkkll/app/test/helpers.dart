import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hhkkll/app.dart';
import 'package:hhkkll/services/controller.dart';
import 'package:hhkkll/services/sound.dart';
import 'package:hhkkll/services/storage.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

late String seedJson;

/// Loads the real Arabic / display fonts and Material icons so widget tests
/// (and screenshots) render actual glyphs instead of the test box font.
Future<void> loadAppFonts() async {
  seedJson = File('assets/data/seed_questions.json').readAsStringSync();
  Future<ByteData> bytes(String path) async => ByteData.sublistView(await File(path).readAsBytes());
  final kufi = FontLoader('Kufi')
    ..addFont(bytes('assets/fonts/NotoKufiArabic-Regular.ttf'))
    ..addFont(bytes('assets/fonts/NotoKufiArabic-Bold.ttf'));
  await kufi.load();
  await (FontLoader('Display')
        ..addFont(bytes('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(bytes('assets/fonts/NotoSans-Bold.ttf')))
      .load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(bytes(icons.path))).load();
    }
  }
}

/// A question source that can be switched off to simulate losing internet.
class FakeOnlineSource implements QuestionSource {
  bool offline = false;
  int calls = 0;
  int _n = 0;
  @override
  String get name => 'fake-server';
  @override
  Future<List<Question>> fetch(Category c, int count, {required List<String> excludeFingerprints}) async {
    calls++;
    if (offline) throw const SocketException('no internet');
    return [
      for (var i = 0; i < count; i++)
        () {
          _n++;
          return Question(
            id: 'live-$_n',
            category: c,
            difficulty: Difficulty.impossible,
            text: 'سؤال مولّد مباشرة رقم $_n عن حدث كروي مختلف $_n',
            answer: 'إجابة $_n',
            items: c == Category.auction ? [for (var k = 0; k < 5; k++) AuctionItem(name: 'عنصر $_n-$k')] : const [],
            clues: c == Category.whoAmI ? ['تلميح أول $_n', 'تلميح ثان $_n', 'تلميح ثالث $_n'] : const [],
            semanticKey: 'live-fact-$_n',
            sources: const [Source(title: 'ref', url: 'https://example.org/ref')],
            createdAt: DateTime.utc(2026, 11, 15),
            verification: const Verification(status: 'verified', method: 'ai-independent-web-verification', model: 'test'),
            origin: 'server',
          );
        }(),
    ];
  }
}

class Harness {
  Harness({MemoryStore? store, List<QuestionSource> sources = const []})
      : store = store ?? MemoryStore(),
        sound = SoundService(enabled: false) {
    controller = AppController(
      files: this.store,
      sound: sound,
      loadSeed: () async => seedJson,
      sourceOverride: sources,
      scheduler: (d, a) => retries.add(a),
    );
  }
  final MemoryStore store;
  final SoundService sound;
  late final AppController controller;
  final List<void Function()> retries = [];

  Future<void> boot(WidgetTester tester, {bool intro = false, Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await controller.init();
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: HhkkllApp(controller: controller, skipIntro: !intro),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final shotKey = GlobalKey();

/// Pumps frames for [ms] (the app has endless ambient animations, so
/// pumpAndSettle would never return).
Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapKey(WidgetTester tester, String key, {int settleMs = 600}) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester, settleMs);
}

Future<void> tapText(WidgetTester tester, String text, {int settleMs = 600}) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester, settleMs);
}

Future<void> addPlayers(AppController c, List<String> names) async {
  for (final n in names) {
    await c.addRosterPlayer(n);
  }
}
