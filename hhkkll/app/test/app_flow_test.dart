import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hhkkll/screens/intro_screen.dart';
import 'package:hhkkll/services/sound.dart';
import 'package:hhkkll/services/storage.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('cinematic intro shows the credits verbatim, then the home screen', (tester) async {
    final h = Harness();
    await h.boot(tester, intro: true);
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text('المطور ابراهيم تاج راسكم'), findsOneWidget);
    expect(find.text('برمجة ابراهيم البو حطة'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2900)); // 5.3 s
    expect(find.text('برمجة ابراهيم البو حطة'), findsOneWidget);
    expect(find.text('المطور ابراهيم تاج راسكم'), findsNothing);
    await tester.pump(const Duration(milliseconds: 3800)); // 9.1 s
    expect(find.text('HHKKLL'), findsOneWidget);
    expect(find.text('استعد للمنافسة...'), findsOneWidget);
    expect(h.sound.played, containsAll([Sfx.introBoom, Sfx.introWhoosh, Sfx.introRise, Sfx.introHit]));
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(tester, 1200);
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.byKey(const Key('new-game')), findsOneWidget);
  });

  testWidgets('intro can be skipped', (tester) async {
    final h = Harness();
    await h.boot(tester, intro: true);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tap(find.byKey(const Key('skip-intro')));
    await settle(tester, 1200);
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.byKey(const Key('new-game')), findsOneWidget);
  });

  testWidgets('players: add, rename and delete', (tester) async {
    final h = Harness();
    await h.boot(tester);
    await tapText(tester, 'إدارة اللاعبين');
    for (final n in ['سالم', 'خالد']) {
      await tapKey(tester, 'add-player');
      await tester.enterText(find.byKey(const Key('name-field')), n);
      await tapKey(tester, 'name-ok');
    }
    expect(find.text('سالم'), findsOneWidget);
    expect(find.text('خالد'), findsOneWidget);
    await tester.tap(find.byTooltip('تعديل الاسم').first);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('name-field')), 'سالم الكبير');
    await tapKey(tester, 'name-ok');
    expect(find.text('سالم الكبير'), findsOneWidget);
    await tester.tap(find.byTooltip('حذف').last);
    await settle(tester);
    expect(find.text('خالد'), findsNothing);
    expect(h.controller.roster.map((p) => p.name), ['سالم الكبير']);
    // Persisted.
    expect(h.store.data['roster'], contains('سالم الكبير'));
  });

  testWidgets('full match: all four sections, strikes, elimination, winner', (tester) async {
    final h = Harness();
    await addPlayers(h.controller, ['أحمد', 'علي', 'سارة']);
    await h.boot(tester);
    final c = h.controller;

    await tapKey(tester, 'new-game');
    await tapKey(tester, 'start-match', settleMs: 900);
    expect(find.text('لوحة المنافسة'), findsOneWidget);
    expect(h.sound.played, contains(Sfx.start));
    final s = c.session!;
    String id(String n) => s.players.firstWhere((p) => p.name == n).id;

    // ---------------- AUCTION ----------------
    await tapKey(tester, 'section-auction', settleMs: 900);
    expect(find.byKey(const Key('question-text')), findsOneWidget);
    final aq = c.session!.used.last;
    expect(aq.category, Category.auction);
    await tapKey(tester, 'bid1-أحمد'); // 1
    await tapKey(tester, 'bid1-علي'); // 2
    await tapKey(tester, 'bid1-أحمد'); // 3
    await tapKey(tester, 'withdraw-علي');
    await tapKey(tester, 'withdraw-سارة');
    expect(find.text('فاز بالمزاد'), findsOneWidget);
    await tapKey(tester, 'close-auction');
    expect(find.text('0 / 3'), findsOneWidget);
    await tapKey(tester, 'toggle-items');
    await tapKey(tester, 'item-0');
    await tapKey(tester, 'item-1');
    await tapKey(tester, 'extra-correct');
    expect(find.text('3 / 3'), findsOneWidget);
    await tapKey(tester, 'resolve-auction', settleMs: 1500);
    expect(s.player(id('أحمد')).score, s.settings.auctionSuccessPoints);
    expect(s.player(id('أحمد')).auctionsWon, 1);
    expect(h.sound.played, containsAll([Sfx.bid, Sfx.auctionWin, Sfx.correct]));
    await tapKey(tester, 'back-to-board', settleMs: 900);

    // ---------------- WHAT DO YOU KNOW ----------------
    await tapKey(tester, 'section-wdyk', settleMs: 900);
    await tapKey(tester, 'chip-علي'); // referee chooses the starting player
    await tapKey(tester, 'pass'); // علي passes → سارة
    expect(s.player(id('علي')).passes, 1);
    await tapKey(tester, 'verdict-wrong', settleMs: 1500); // سارة strike
    expect(s.player(id('سارة')).strikes, 1);
    await tapKey(tester, 'verdict-correct', settleMs: 1500); // أحمد correct
    expect(s.player(id('أحمد')).score, s.settings.auctionSuccessPoints + s.settings.wdykPoints);
    await tapKey(tester, 'next-question', settleMs: 900);
    expect(c.session!.used.where((u) => u.category == Category.whatDoYouKnow).length, 2);
    await tapKey(tester, 'round-close', settleMs: 300);
    // Round not decided → confirmation.
    await tapText(tester, 'تأكيد', settleMs: 900);

    // ---------------- BUZZER ----------------
    await tapKey(tester, 'section-buzzer', settleMs: 900);
    expect(find.byKey(const Key('question-text')), findsNothing, reason: 'hidden until START');
    await tapKey(tester, 'buzzer-start', settleMs: 100);
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester, 300);
    expect(find.byKey(const Key('question-text')), findsOneWidget);
    // سارة presses first, then علي in the same frame: only سارة counts.
    await tester.tap(find.byKey(const Key('buzz-سارة')));
    await tester.tap(find.byKey(const Key('buzz-علي')));
    await settle(tester, 400);
    expect(find.byKey(const Key('buzz-winner')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('buzz-winner')), matching: find.text('سارة')), findsNothing);
    expect((tester.widget(find.byKey(const Key('buzz-winner'))) as Text).data, 'سارة');
    expect(s.player(id('سارة')).firstBuzzes, 1);
    expect(s.player(id('علي')).firstBuzzes, 0);
    expect(h.sound.played, contains(Sfx.buzzer));
    await tapKey(tester, 'verdict-wrong', settleMs: 1500); // سارة strike 2
    expect(s.player(id('سارة')).strikes, 2);
    await tapKey(tester, 'buzzer-reopen', settleMs: 3400);
    await tester.tap(find.byKey(const Key('buzz-سارة'))); // locked out
    await tester.tap(find.byKey(const Key('buzz-علي')));
    await settle(tester, 400);
    expect((tester.widget(find.byKey(const Key('buzz-winner'))) as Text).data, 'علي');
    await tapKey(tester, 'verdict-correct', settleMs: 1500);
    expect(s.player(id('علي')).score, s.settings.buzzerPoints);
    await tapKey(tester, 'back-to-board', settleMs: 900);

    // ---------------- STRIKE 3 → ELIMINATION (referee panel) ----------------
    await tapKey(tester, 'hub-referee', settleMs: 900);
    final addStrike = find.descendant(of: find.byKey(const Key('ref-سارة')), matching: find.byTooltip('إضافة خطأ'));
    await tester.tap(addStrike);
    await settle(tester, 500);
    expect(find.text('إقصاء!'), findsOneWidget);
    expect(s.player(id('سارة')).eliminated, isTrue);
    expect(h.sound.played, contains(Sfx.eliminated));
    await settle(tester, 3000);
    // Restore and eliminate again from the panel.
    await tester.tap(find.descendant(of: find.byKey(const Key('ref-سارة')), matching: find.text('إعادة اللاعب')));
    await settle(tester);
    expect(s.player(id('سارة')).eliminated, isFalse);
    expect(s.player(id('سارة')).strikes, s.settings.strikeLimit - 1);
    await tester.tap(find.descendant(of: find.byKey(const Key('ref-سارة')), matching: find.byTooltip('إضافة نقاط')));
    await settle(tester);
    expect(s.player(id('سارة')).score, -s.settings.buzzerWrongPenalty + 5); // one wrong buzz, then +5 from the referee
    await tester.tapAt(const Offset(200, 40)); // close sheet
    await settle(tester, 900);

    // ---------------- WHO AM I ----------------
    await tapKey(tester, 'section-whoami', settleMs: 900);
    expect(find.byKey(const Key('clue-0')), findsNothing);
    await tapKey(tester, 'reveal-clue');
    expect(find.byKey(const Key('clue-0')), findsOneWidget);
    await tapKey(tester, 'reveal-clue');
    expect(find.text('قيمة الإجابة الآن: 40'), findsOneWidget);
    await tapKey(tester, 'chip-علي');
    await tapKey(tester, 'verdict-wrong', settleMs: 1300);
    await tapKey(tester, 'chip-أحمد');
    await tapKey(tester, 'verdict-correct', settleMs: 1500);
    expect(s.player(id('أحمد')).score, s.settings.auctionSuccessPoints + s.settings.wdykPoints + 40);
    await tapKey(tester, 'back-to-board', settleMs: 900);

    // No question was ever repeated.
    final ids = c.session!.used.map((u) => u.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, 5);

    // ---------------- END ----------------
    await tapKey(tester, 'end-game', settleMs: 400);
    await tapKey(tester, 'confirm-end', settleMs: 3000);
    expect((tester.widget(find.byKey(const Key('winner-name'))) as Text).data, 'أحمد');
    expect(h.sound.played, contains(Sfx.winner));
    expect(c.session, isNull);
    expect(c.history.single.players.first.name, 'أحمد');
    expect(h.store.data['history'], contains('أحمد'));
    // Used questions moved to the cross-session history.
    expect(c.supply.historySize, 5);
  });

  testWidgets('a match survives an app restart mid-round', (tester) async {
    final store = MemoryStore();
    final h = Harness(store: store);
    await addPlayers(h.controller, ['نور', 'ليث']);
    await h.boot(tester);
    await tapKey(tester, 'new-game');
    await tapKey(tester, 'start-match', settleMs: 900);
    await tapKey(tester, 'section-auction', settleMs: 900);
    await tapKey(tester, 'bid1-نور');
    await tapKey(tester, 'bid1-ليث');
    final usedId = h.controller.session!.used.single.id;
    await tester.pumpWidget(const SizedBox()); // "kill" the app
    await settle(tester, 100);

    final h2 = Harness(store: store); // same storage = restart
    await h2.boot(tester);
    expect(find.byKey(const Key('resume-game')), findsOneWidget);
    await tapKey(tester, 'resume-game', settleMs: 900);
    await tapKey(tester, 'resume-round', settleMs: 900);
    expect(find.text('ليث'), findsWidgets);
    expect(find.text('2'), findsWidgets); // high bid restored
    final r = h2.controller.pendingRound!.$1 as AuctionRound;
    expect(r.highestBid, 2);
    // The used question is still blocked after restart.
    expect(h2.controller.supply.peekQueue(Category.auction).any((q) => q.id == usedId), isFalse);
  });

  testWidgets('online generation, offline fallback and automatic reconnection', (tester) async {
    final src = FakeOnlineSource();
    final h = Harness(sources: [src]);
    await addPlayers(h.controller, ['أ', 'ب']);
    await h.boot(tester);
    await tapKey(tester, 'new-game');
    await tapKey(tester, 'start-match', settleMs: 900);
    final c = h.controller;
    expect(src.calls, 4, reason: 'one request per section on session start, no button needed');
    expect(c.supply.status.online, isTrue);
    expect(c.supply.cachedQuestions.where((q) => q.origin == 'server').length, 24);

    // Internet drops: play continues from the local reserve.
    src.offline = true;
    // 12 starter + 6 live buzzer questions are queued; draw down past the
    // refill threshold so the supply tries (and fails) to fetch.
    for (var i = 0; i < 15; i++) {
      final q = c.drawQuestion(Category.buzzer);
      expect(q, isNotNull, reason: 'draw $i must not stop the game');
    }
    await settle(tester, 200);
    expect(c.supply.status.online, isFalse);
    expect(h.retries, isNotEmpty, reason: 'a reconnection is scheduled automatically');
    await settle(tester, 300);
    expect(find.text('لوحة المنافسة'), findsOneWidget);

    // Internet returns: the scheduled retry resumes generation by itself.
    src.offline = false;
    final before = src.calls;
    for (final r in List.of(h.retries)) {
      r();
    }
    await settle(tester, 200);
    expect(src.calls, greaterThan(before));
    expect(c.supply.status.online, isTrue);
    final ids = c.session!.used.map((u) => u.id);
    expect(ids.toSet().length, ids.length);
  });

  testWidgets('settings: mute and rules persist', (tester) async {
    final h = Harness();
    await h.boot(tester);
    await tapText(tester, 'الإعدادات');
    await tapKey(tester, 'mute');
    expect(h.controller.settings.muted, isTrue);
    expect(h.sound.muted, isTrue);
    expect(h.store.data['settings'], contains('"muted":true'));
  });
}
