// Renders the main screens to PNG for design review and the docs.
//   HHKKLL_SHOTS=1 flutter test test/screenshots_test.dart
// Output: hhkkll/docs/screenshots/*.png (skipped unless HHKKLL_SHOTS is set).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final _enabled = Platform.environment['HHKKLL_SHOTS'] == '1';

Future<void> shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('../docs/screenshots/$name.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('screenshots', skip: !_enabled, (tester) async {
    final h = Harness();
    await addPlayers(h.controller, ['أحمد', 'علي', 'سارة', 'يوسف']);
    await h.boot(tester, intro: true);
    await tester.pump(const Duration(milliseconds: 2300));
    await shot(tester, '01_intro_developer');
    await tester.pump(const Duration(milliseconds: 2900));
    await shot(tester, '02_intro_programmer');
    await tester.pump(const Duration(milliseconds: 3800));
    await shot(tester, '03_intro_logo');
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(tester, 1500);
    await shot(tester, '04_home');

    await tapKey(tester, 'new-game');
    await shot(tester, '05_new_game');
    await tapKey(tester, 'start-match', settleMs: 900);
    final s = h.controller.session!;
    s.recordCorrect(s.players[1].id, 45);
    s.recordCorrect(s.players[0].id, 30);
    s.addStrike(s.players[2].id);
    s.addStrike(s.players[3].id);
    s.addStrike(s.players[3].id);
    await h.controller.persistSession();
    await settle(tester);
    await shot(tester, '06_hub');

    await tapKey(tester, 'section-auction', settleMs: 900);
    await tapKey(tester, 'bid1-أحمد');
    await tapKey(tester, 'bid1-علي');
    await tapKey(tester, 'bidx-سارة');
    await tester.enterText(find.byKey(const Key('bid-field')), '5');
    await tapKey(tester, 'bid-ok');
    await shot(tester, '07_auction_bidding');
    await tapKey(tester, 'withdraw-أحمد');
    await tapKey(tester, 'withdraw-علي');
    await tapKey(tester, 'withdraw-يوسف');
    await tapKey(tester, 'close-auction');
    await tapKey(tester, 'toggle-items');
    await tapKey(tester, 'item-0');
    await tapKey(tester, 'item-3');
    await tester.pump(const Duration(seconds: 3));
    await shot(tester, '08_auction_answering');
    await tapKey(tester, 'resolve-auction', settleMs: 400);
    await settle(tester, 1500);
    await tapKey(tester, 'back-to-board', settleMs: 900);

    await tapKey(tester, 'section-wdyk', settleMs: 900);
    await tapKey(tester, 'pass');
    await shot(tester, '09_what_do_you_know');
    await tapKey(tester, 'verdict-wrong', settleMs: 300);
    await shot(tester, '10_strike_flash');
    await settle(tester, 1500);
    await tapKey(tester, 'round-close', settleMs: 300);
    await tapText(tester, 'تأكيد', settleMs: 900);

    await tapKey(tester, 'section-buzzer', settleMs: 900);
    await shot(tester, '11_buzzer_ready');
    await tapKey(tester, 'buzzer-start', settleMs: 300);
    await shot(tester, '12_buzzer_countdown');
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await settle(tester, 300);
    await shot(tester, '13_buzzer_open');
    await tester.tap(find.byKey(const Key('buzz-سارة')));
    await settle(tester, 800);
    await shot(tester, '14_buzzer_locked');
    await tapKey(tester, 'verdict-correct', settleMs: 1500);
    await tapKey(tester, 'back-to-board', settleMs: 900);

    await tapKey(tester, 'section-whoami', settleMs: 900);
    await tapKey(tester, 'reveal-clue');
    await tapKey(tester, 'reveal-clue');
    await tapKey(tester, 'chip-علي');
    await shot(tester, '15_who_am_i');
    await tapKey(tester, 'round-close', settleMs: 300);
    await tapText(tester, 'تأكيد', settleMs: 900);

    await tapKey(tester, 'hub-referee', settleMs: 900);
    await shot(tester, '16_referee_panel');
    await tester.tapAt(const Offset(200, 40));
    await settle(tester, 900);

    await tapKey(tester, 'end-game', settleMs: 400);
    await tapKey(tester, 'confirm-end', settleMs: 3000);
    await shot(tester, '17_winner');
  });

  testWidgets('tablet screenshots', skip: !_enabled, (tester) async {
    final h = Harness();
    await addPlayers(h.controller, ['أحمد', 'علي', 'سارة', 'يوسف', 'مريم', 'حسن']);
    await h.boot(tester, size: const Size(1280, 800));
    await settle(tester);
    await shot(tester, '20_tablet_home');
    await tapKey(tester, 'new-game');
    await tapKey(tester, 'start-match', settleMs: 900);
    await tapKey(tester, 'section-buzzer', settleMs: 900);
    await tapKey(tester, 'buzzer-start', settleMs: 300);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await settle(tester, 300);
    await tester.tap(find.byKey(const Key('buzz-مريم')));
    await settle(tester, 800);
    await shot(tester, '21_tablet_buzzer');
  });
}
