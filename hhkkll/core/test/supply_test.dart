import 'dart:async';

import 'package:hhkkll_core/hhkkll_core.dart';
import 'package:test/test.dart';

class MemCache implements QuestionCache {
  List<Question> saved = [];
  @override
  Future<List<Question>> loadAll() async => saved;
  @override
  Future<void> saveAll(List<Question> questions) async => saved = [...questions];
}

class MemHistory implements HistoryStore {
  List<DedupEntry> saved = [];
  @override
  Future<List<DedupEntry>> load() async => saved;
  @override
  Future<void> save(List<DedupEntry> entries) async => saved = [...entries];
}

/// Generates distinct questions on demand; can be switched offline. Every
/// third batch also re-sends an already-served question (a duplicate).
class FakeSource implements QuestionSource {
  bool offline = false;
  int calls = 0;
  int _n = 0;
  final List<List<String>> excludes = [];
  final List<Question> served = [];

  @override
  String get name => 'fake';

  @override
  Future<List<Question>> fetch(Category c, int count,
      {required List<String> excludeFingerprints}) async {
    calls++;
    excludes.add(excludeFingerprints);
    if (offline) throw StateError('offline');
    final out = <Question>[];
    for (var i = 0; i < count; i++) {
      _n++;
      out.add(make(c, 'gen-$_n', 'سؤال رقم $_n عن حدث مختلف تماماً $_n', 'جواب$_n'));
    }
    final again = served.where((q) => q.category == c);
    if (calls % 3 == 0 && again.isNotEmpty) out.add(again.first);
    served.addAll(out);
    return out;
  }
}

Question make(Category c, String id, String text, String answer) => Question(
      id: id,
      category: c,
      difficulty: Difficulty.veryExpert,
      text: text,
      answer: answer,
      items: c == Category.auction
          ? [for (var i = 0; i < 4; i++) AuctionItem(name: '$answer-عنصر-$i')]
          : const [],
      clues: c == Category.whoAmI ? ['$text أ', '$text ب', '$text ج'] : const [],
      semanticKey: 'fact:$id',
      sources: const [Source(title: 'ref', url: 'https://example.org/ref')],
      createdAt: DateTime.utc(2026),
      verification: const Verification(status: 'verified', method: 'test'),
      origin: 'server',
    );

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeSource src;
  late MemCache cache;
  late MemHistory hist;
  late List<(Duration, void Function())> scheduled;
  late QuestionSupply supply;

  setUp(() {
    src = FakeSource();
    cache = MemCache();
    hist = MemHistory();
    scheduled = [];
    supply = QuestionSupply(
      sources: [src],
      cache: cache,
      history: hist,
      lowWatermark: 3,
      batchSize: 5,
      scheduler: (d, a) => scheduled.add((d, a)),
    );
  });

  test('starting a session fetches every section automatically', () async {
    await supply.init();
    await supply.startSession();
    await settle();
    for (final c in Category.values) {
      expect(supply.queued(c), 5, reason: c.code);
    }
    expect(src.calls, 4);
  });

  test('background refill when a section runs low, never repeating', () async {
    await supply.init();
    await supply.startSession();
    await settle();
    final seen = <String>{};
    for (var i = 0; i < 40; i++) {
      final q = supply.next(Category.buzzer);
      await settle();
      expect(q, isNotNull, reason: 'iteration $i — supply must keep up');
      expect(seen.add(q!.id), isTrue, reason: 'question ${q.id} repeated');
    }
    expect(supply.status.rejectedDuplicates, greaterThan(0),
        reason: 'the fake source re-sends duplicates, they must be dropped');
    // The server is told which facts to avoid.
    expect(src.excludes.last, isNotEmpty);
  });

  test('offline: keeps serving from the cache and retries with back-off', () async {
    // First session online fills the cache.
    await supply.init();
    await supply.startSession();
    await settle();
    await supply.endSession();

    src.offline = true;
    final s2 = QuestionSupply(
      sources: [src],
      cache: cache,
      history: hist,
      lowWatermark: 3,
      batchSize: 5,
      scheduler: (d, a) => scheduled.add((d, a)),
    );
    await s2.init();
    expect(s2.cachedQuestions.length, 20);
    // Nothing was taken in session 1, so all 20 are fresh for session 2.
    await s2.startSession();
    await settle();
    expect(s2.status.online, isFalse);
    expect(s2.queued(Category.whoAmI), 5);
    expect(s2.next(Category.whoAmI), isNotNull);
    expect(scheduled, isNotEmpty);
    final firstDelay = scheduled.first.$1;

    // Still offline at the retry: delay grows.
    final retry = scheduled.removeLast();
    retry.$2();
    await settle();
    expect(scheduled.last.$1 > firstDelay, isTrue);

    // Internet is back: the retry fetches without any user action.
    src.offline = false;
    final callsBefore = src.calls;
    scheduled.removeLast().$2();
    await settle();
    expect(src.calls, greaterThan(callsBefore));
    expect(s2.status.online, isTrue);
  });

  test('questions used in a previous session are served only as a last resort',
      () async {
    await supply.init();
    await supply.startSession();
    await settle();
    final used = supply.next(Category.whatDoYouKnow)!;
    await supply.endSession();
    expect(hist.saved.map((e) => e.id), contains(used.id));

    src.offline = true;
    final s2 = QuestionSupply(
        sources: [src], cache: cache, history: hist, lowWatermark: 3, batchSize: 5,
        scheduler: (d, a) {});
    await s2.init();
    await s2.startSession();
    await settle();
    final ids = s2.peekQueue(Category.whatDoYouKnow).map((q) => q.id);
    // Plenty of fresh ones exist, so the used question is not re-queued.
    expect(ids, isNot(contains(used.id)));
  });

  test('resuming a saved match restores the session index', () async {
    await supply.init();
    final prior = make(Category.buzzer, 'old', 'سؤال قديم في هذه المباراة', 'قديم');
    src.served.add(prior);
    await supply.startSession(alreadyUsed: [prior]);
    await settle();
    expect(supply.usedThisSession.map((q) => q.id), ['old']);
    // The fake source re-sends served.first (prior) every third call; it must
    // never be queued.
    for (var i = 0; i < 6; i++) {
      supply.refillNow(Category.buzzer);
      await settle();
    }
    expect(supply.peekQueue(Category.buzzer).map((q) => q.id), isNot(contains('old')));
  });

  test('invalid questions from a source are rejected', () async {
    final bad = _BadSource();
    final s = QuestionSupply(sources: [bad], cache: cache, history: hist, scheduler: (d, a) {});
    await s.init();
    await s.startSession();
    await settle();
    expect(s.queued(Category.auction), 0);
    expect(s.status.rejectedInvalid, greaterThan(0));
  });
}

class _BadSource implements QuestionSource {
  @override
  String get name => 'bad';
  @override
  Future<List<Question>> fetch(Category c, int count,
          {required List<String> excludeFingerprints}) async =>
      [
        Question(
          id: 'x-${c.code}',
          category: c,
          difficulty: Difficulty.hard,
          text: 'سؤال بدون مصدر',
          answer: 'x',
          sources: const [],
          createdAt: DateTime.utc(2026),
          verification: const Verification(status: 'verified', method: 't'),
        ),
      ];
}
