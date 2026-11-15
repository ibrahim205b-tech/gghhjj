import 'dart:convert';

import 'package:hhkkll_core/hhkkll_core.dart';
import 'package:test/test.dart';

GameSession session([int n = 3]) => GameSession(
      id: 's',
      players: [
        for (var i = 1; i <= n; i++) PlayerState(id: 'p$i', name: 'لاعب $i'),
      ],
      settings: GameSettings(),
    );

T roundTrip<T extends Round>(T r) =>
    Round.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>) as T;

void main() {
  group('scoreboard', () {
    test('three strikes eliminate, restore brings the player back', () {
      final s = session();
      expect(s.addStrike('p1').eliminatedNow, isFalse);
      expect(s.addStrike('p1').eliminatedNow, isFalse);
      final r = s.addStrike('p1');
      expect(r.eliminatedNow, isTrue);
      expect(s.player('p1').eliminated, isTrue);
      expect(s.activePlayers.map((p) => p.id), ['p2', 'p3']);
      s.restore('p1');
      expect(s.player('p1').eliminated, isFalse);
      expect(s.player('p1').strikes, 2);
      s.removeStrike('p1');
      expect(s.player('p1').strikes, 1);
    });

    test('ranking: score, then correct answers, then fewer strikes', () {
      final s = session();
      s.recordCorrect('p2', 10);
      s.addPoints('p3', 10);
      s.addStrike('p3');
      expect(s.ranking.map((p) => p.id), ['p2', 'p3', 'p1']);
    });

    test('session JSON round-trip keeps everything', () {
      final s = session();
      s.recordCorrect('p1', 30);
      s.addStrike('p2');
      s.activeRound = {'kind': 'x'};
      final c = GameSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(c.player('p1').score, 30);
      expect(c.player('p1').correct, 1);
      expect(c.player('p2').strikes, 1);
      expect(c.log.length, s.log.length);
      expect(c.activeRound, {'kind': 'x'});
    });
  });

  group('auction', () {
    test('bids must rise, withdrawals decide the winner, success scores', () {
      final s = session();
      final a = AuctionRound(questionId: 'q', participants: ['p1', 'p2', 'p3'], maxBid: 8);
      a.bid('p1', 3);
      expect(() => a.bid('p2', 3), throwsA(isA<RoundError>()));
      a.bid('p2', 5);
      expect(() => a.bid('p3', 9), throwsA(isA<RoundError>()));
      expect(() => a.withdraw('p2'), throwsA(isA<RoundError>()));
      a.withdraw('p1');
      expect(a.decided, isFalse);
      a.withdraw('p3');
      expect(a.decided, isTrue);
      expect(a.highestBidder, 'p2');
      a.startAnswering();
      for (final i in [0, 1, 2, 3]) {
        a.toggleItem(i);
      }
      a.addExtraCorrect();
      expect(a.correctCount, 5);
      final o = a.resolve(s);
      expect(o.success, isTrue);
      expect(s.player('p2').score, s.settings.auctionSuccessPoints);
      expect(s.player('p2').auctionsWon, 1);
    });

    test('failure applies penalty and a strike; undo removes the last bid', () {
      final s = session();
      final a = AuctionRound(questionId: 'q', participants: ['p1', 'p2']);
      a.bid('p1', 4);
      a.bid('p2', 6);
      a.undoBid();
      expect(a.highestBidder, 'p1');
      a.startAnswering();
      a.toggleItem(0);
      a.toggleItem(0); // un-mark
      a.toggleItem(1);
      final o = a.resolve(s);
      expect(o.success, isFalse);
      expect(o.achieved, 1);
      expect(s.player('p1').score, -s.settings.auctionFailPenalty);
      expect(s.player('p1').strikes, 1);
    });

    test('survives serialisation mid-answer', () {
      final a = AuctionRound(questionId: 'q', participants: ['p1', 'p2']);
      a.bid('p2', 2);
      a.withdraw('p1');
      a.startAnswering();
      a.toggleItem(3);
      final b = roundTrip(a);
      expect(b.phase, AuctionPhase.answering);
      expect(b.highestBidder, 'p2');
      expect(b.namedItems, {3});
    });
  });

  group('what do you know (PASS / STRIKE)', () {
    test('order starts at the chosen player and wraps', () {
      final s = session(4);
      final r = WdykRound.start(s, 'q', 'p3');
      expect(r.order, ['p3', 'p4', 'p1', 'p2']);
      expect(r.current, 'p3');
    });

    test('pass moves to next, wrong adds a strike, correct scores', () {
      final s = session();
      final r = WdykRound.start(s, 'q', 'p1');
      final o1 = r.pass(s);
      expect(o1.result, TurnResult.passed);
      expect(o1.next, 'p2');
      expect(s.player('p1').passes, 1);
      final o2 = r.wrong(s);
      expect(o2.result, TurnResult.wrong);
      expect(s.player('p2').strikes, 1);
      expect(r.current, 'p3');
      r.correct(s);
      expect(s.player('p3').score, s.settings.wdykPoints);
      expect(r.done, isTrue);
    });

    test('third strike eliminates and the player is skipped afterwards', () {
      final s = session();
      s.addStrike('p1');
      s.addStrike('p1');
      final r = WdykRound.start(s, 'q', 'p1');
      final o = r.wrong(s);
      expect(o.result, TurnResult.eliminated);
      expect(s.player('p1').eliminated, isTrue);
      final r2 = WdykRound.start(s, 'q2', 'p2');
      expect(r2.order, isNot(contains('p1')));
    });

    test('round ends when everybody passed or failed', () {
      final s = session(2);
      final r = WdykRound.start(s, 'q', 'p1');
      r.pass(s);
      final o = r.wrong(s);
      expect(o.result, TurnResult.exhausted);
      expect(r.done, isTrue);
    });

    test('serialises', () {
      final s = session();
      final r = WdykRound.start(s, 'q', 'p2')..pass(s);
      final c = roundTrip(r);
      expect(c.current, 'p3');
      expect(c.tried, {'p2'});
    });
  });

  group('buzzer', () {
    test('only the first press is accepted and others are locked', () {
      final s = session();
      final b = BuzzerRound(questionId: 'q');
      expect(b.press(s, 'p1', 0).accepted, isFalse, reason: 'not open yet');
      b.startCountdown();
      b.open(1000000);
      final first = b.press(s, 'p2', 1250000);
      final second = b.press(s, 'p1', 1250001);
      expect(first.accepted, isTrue);
      expect(first.reactionMs, 250);
      expect(second.accepted, isFalse);
      expect(b.lockedBy, 'p2');
      expect(s.player('p2').firstBuzzes, 1);
    });

    test('wrong answer: strike, locked out, re-open for the others', () {
      final s = session();
      final b = BuzzerRound(questionId: 'q')..open(0);
      b.press(s, 'p1', 10);
      final o = b.wrong(s);
      expect(o.result, TurnResult.wrong);
      expect(s.player('p1').strikes, 1);
      expect(s.player('p1').score, -s.settings.buzzerWrongPenalty);
      expect(b.phase, BuzzerPhase.judged);
      b.reopen(100);
      expect(b.press(s, 'p1', 120).accepted, isFalse);
      expect(b.press(s, 'p3', 130).accepted, isTrue);
      b.correct(s);
      expect(s.player('p3').score, s.settings.buzzerPoints);
      expect(b.done, isTrue);
    });

    test('closes itself when every active player answered wrong', () {
      final s = session(2);
      final b = BuzzerRound(questionId: 'q')..open(0);
      b.press(s, 'p1', 1);
      b.wrong(s);
      b.reopen(2);
      b.press(s, 'p2', 3);
      b.wrong(s);
      expect(b.done, isTrue);
    });

    test('eliminated players cannot buzz', () {
      final s = session();
      s.eliminate('p1');
      final b = BuzzerRound(questionId: 'q')..open(0);
      expect(b.press(s, 'p1', 1).accepted, isFalse);
    });

    test('an open buzzer resumes as ready after a restart', () {
      final b = BuzzerRound(questionId: 'q')..open(0);
      expect(roundTrip(b).phase, BuzzerPhase.ready);
    });
  });

  group('who am I', () {
    test('earlier clue = more points', () {
      final s = session();
      final w = WhoAmIRound(questionId: 'q', clueCount: 5);
      expect(w.canAttempt(s, 'p1'), isFalse, reason: 'no clue revealed');
      w.revealNext();
      w.revealNext();
      expect(w.currentPoints(s), 40);
      w.correct(s, 'p1');
      expect(s.player('p1').score, 40);
    });

    test('wrong guess locks the player until the next clue', () {
      final s = session();
      final w = WhoAmIRound(questionId: 'q', clueCount: 3)..revealNext();
      w.wrong(s, 'p1');
      expect(w.canAttempt(s, 'p1'), isFalse);
      expect(() => w.correct(s, 'p1'), throwsA(isA<RoundError>()));
      w.revealNext();
      expect(w.canAttempt(s, 'p1'), isTrue);
      w.revealNext();
      expect(w.canReveal, isFalse);
      w.correct(s, 'p1');
      expect(s.player('p1').score, 30);
    });

    test('optional strike on wrong guess', () {
      final s = session()..settings.whoAmIStrikeOnWrong = true;
      final w = WhoAmIRound(questionId: 'q', clueCount: 3)..revealNext();
      w.wrong(s, 'p2');
      expect(s.player('p2').strikes, 1);
    });
  });
}
