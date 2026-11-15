import 'dart:async';
import 'dart:math';

import 'dedup.dart';
import 'question.dart';

/// Somewhere new questions come from (live backend, published feed...).
abstract class QuestionSource {
  String get name;

  /// Fetches up to [count] questions of [category]. [excludeFingerprints]
  /// lists semantic fingerprints already used / queued in this session so a
  /// server can avoid generating them again.
  Future<List<Question>> fetch(
    Category category,
    int count, {
    required List<String> excludeFingerprints,
  });
}

/// Local persistent store for every question received (offline reserve).
abstract class QuestionCache {
  Future<List<Question>> loadAll();
  Future<void> saveAll(List<Question> questions);
}

/// Persists the cross-session history (dedup entries of used questions).
abstract class HistoryStore {
  Future<List<DedupEntry>> load();
  Future<void> save(List<DedupEntry> entries);
}

class SupplyStatus {
  const SupplyStatus({
    required this.online,
    required this.fetching,
    required this.queued,
    required this.cached,
    required this.usedThisSession,
    required this.rejectedDuplicates,
    required this.rejectedInvalid,
    this.lastError,
    this.lastSuccess,
    this.lastSource,
  });
  final bool online;
  final Set<Category> fetching;
  final Map<Category, int> queued;
  final int cached;
  final int usedThisSession;
  final int rejectedDuplicates;
  final int rejectedInvalid;
  final String? lastError;
  final DateTime? lastSuccess;
  final String? lastSource;
}

typedef Scheduler = void Function(Duration delay, void Function() action);

void _defaultScheduler(Duration d, void Function() a) => Timer(d, a);

/// Keeps every section stocked with fresh, never-repeated questions during a
/// session — automatically, in the background, without the referee pressing
/// anything.
///
/// * Each section has a queue. When it drops to [lowWatermark] the supply asks
///   the sources for another batch.
/// * Every incoming question is validated and checked against the session's
///   [DedupIndex] (used + queued). Duplicates are dropped.
/// * Questions used in previous sessions are kept in a history index; they
///   are only served again once nothing fresher is available.
/// * When every source fails (no internet) the queue is served from the local
///   cache, and fetching is retried with exponential back-off until it works.
class QuestionSupply {
  QuestionSupply({
    required this.sources,
    required this.cache,
    required this.history,
    this.lowWatermark = 4,
    this.batchSize = 6,
    this.maxCached = 3000,
    this.maxQueue = 30,
    this.maxBackoff = const Duration(seconds: 60),
    Scheduler? scheduler,
    this.onChange,
  }) : _schedule = scheduler ?? _defaultScheduler;

  final List<QuestionSource> sources;
  final QuestionCache cache;
  final HistoryStore history;
  final int lowWatermark;
  final int batchSize;
  final int maxCached;

  /// Questions kept ready per section (the rest stay in the cache).
  final int maxQueue;
  final Duration maxBackoff;
  final Scheduler _schedule;
  void Function()? onChange;

  final Map<Category, List<Question>> _queues = {
    for (final c in Category.values) c: <Question>[],
  };
  final Map<String, Question> _cached = {};
  final DedupIndex _session = DedupIndex();
  final DedupIndex _history = DedupIndex();
  final Set<Category> _fetching = {};
  final Map<Category, int> _failures = {};
  final Map<Category, int> _empty = {};
  final Set<Category> _retryScheduled = {};
  final List<Question> _usedThisSession = [];
  bool _online = true;
  bool _active = false;
  int _rejectedDup = 0;
  int _rejectedInvalid = 0;
  String? _lastError;
  DateTime? _lastSuccess;
  String? _lastSource;
  int _generation = 0;

  bool get active => _active;
  List<Question> get usedThisSession => List.unmodifiable(_usedThisSession);
  Iterable<Question> get cachedQuestions => _cached.values;
  int queued(Category c) => _queues[c]!.length;
  List<Question> peekQueue(Category c) => List.unmodifiable(_queues[c]!);

  SupplyStatus get status => SupplyStatus(
        online: _online,
        fetching: {..._fetching},
        queued: {for (final c in Category.values) c: _queues[c]!.length},
        cached: _cached.length,
        usedThisSession: _usedThisSession.length,
        rejectedDuplicates: _rejectedDup,
        rejectedInvalid: _rejectedInvalid,
        lastError: _lastError,
        lastSuccess: _lastSuccess,
        lastSource: _lastSource,
      );

  /// Loads the local cache (questions + cross-session history) once.
  Future<void> init() async {
    for (final q in await cache.loadAll()) {
      if (q.validate().isEmpty) _cached[q.id] = q;
    }
    _history.clear();
    for (final e in await history.load()) {
      _history.add(e);
    }
    _notify();
  }

  /// Starts a new session: clears the session index and queues, fills the
  /// queues from the cache and starts background fetching.
  ///
  /// [alreadyUsed] restores the session index when resuming a saved match.
  Future<void> startSession({List<Question> alreadyUsed = const []}) async {
    _generation++;
    _active = true;
    _failures.clear();
    _empty.clear();
    _retryScheduled.clear(); // stale timers check _generation and do nothing
    _session.clear();
    _usedThisSession.clear();
    for (final c in Category.values) {
      _queues[c]!.clear();
    }
    for (final q in alreadyUsed) {
      _session.addQuestion(q);
      _usedThisSession.add(q);
    }
    _fillFromCache();
    _notify();
    // Always ask for fresh questions at session start, even when the cache
    // could cover the first rounds.
    for (final c in Category.values) {
      _maybeRefill(c, force: true);
    }
  }

  /// Ends the session: used questions go to the persistent history.
  Future<void> endSession() async {
    _active = false;
    _generation++;
    for (final q in _usedThisSession) {
      if (!_history.containsId(q.id)) _history.addQuestion(q);
    }
    await history.save(_history.entries.toList());
    for (final c in Category.values) {
      _queues[c]!.clear();
    }
    _notify();
  }

  /// Puts cached questions that are not duplicates into the queues. Fresh
  /// (never used in earlier sessions) questions come first; history ones are
  /// used only for sections that would otherwise be empty.
  void _fillFromCache() {
    final fresh = <Question>[];
    final old = <Question>[];
    for (final q in _cached.values) {
      if (_session.check(q) != null) continue;
      (_history.check(q) == null ? fresh : old).add(q);
    }
    final rnd = Random();
    fresh.shuffle(rnd);
    old.shuffle(rnd);
    for (final q in fresh) {
      if (_queues[q.category]!.length >= maxQueue) continue;
      if (_session.tryAdd(q) == null) _queues[q.category]!.add(q);
    }
    for (final c in Category.values) {
      if (_queues[c]!.length >= lowWatermark) continue;
      for (final q in old.where((q) => q.category == c)) {
        if (_queues[c]!.length >= lowWatermark * 2) break;
        if (_session.tryAdd(q) == null) _queues[c]!.add(q);
      }
    }
  }

  /// Takes the next question of [category] and records it as used in this
  /// session. Returns null if the section is empty (the background fetch is
  /// already running in that case).
  Question? next(Category category) {
    final q = _queues[category]!;
    if (q.isEmpty) {
      _maybeRefill(category);
      return null;
    }
    final question = q.removeAt(0);
    _usedThisSession.add(question);
    _maybeRefill(category);
    _notify();
    return question;
  }

  /// A specific question chosen by the referee from the queue.
  Question? take(String questionId) {
    for (final c in Category.values) {
      final q = _queues[c]!;
      final i = q.indexWhere((e) => e.id == questionId);
      if (i >= 0) {
        final question = q.removeAt(i);
        _usedThisSession.add(question);
        _maybeRefill(c);
        _notify();
        return question;
      }
    }
    return null;
  }

  /// Forces a fetch now (e.g. when the referee opens the question bank).
  void refillNow(Category c) {
    _failures[c] = 0;
    _maybeRefill(c, force: true);
  }

  void _maybeRefill(Category c, {bool force = false}) {
    if (!_active) return;
    if (_fetching.contains(c)) return;
    if (!force && _queues[c]!.length > lowWatermark) return;
    if (!force && _retryScheduled.contains(c)) return;
    unawaited(_refill(c));
  }

  Future<void> _refill(Category c) async {
    final gen = _generation;
    _fetching.add(c);
    _notify();
    var gotAny = false;
    String? error;
    for (final src in sources) {
      try {
        final batch = await src.fetch(
          c,
          batchSize,
          excludeFingerprints: _session.entries
              .where((e) => e.category == c)
              .map((e) => e.semanticFp)
              .toList(),
        );
        if (gen != _generation) return;
        _online = true;
        gotAny = true;
        _lastSuccess = DateTime.now();
        _lastSource = src.name;
        _ingest(c, batch);
        if (_queues[c]!.length > lowWatermark) break;
      } catch (e) {
        error = '${src.name}: $e';
      }
    }
    if (gen != _generation) return;
    _fetching.remove(c);
    if (gotAny) {
      _failures[c] = 0;
      _lastError = null;
      // Connected but the section is still low (e.g. the server is still
      // generating): ask again shortly, backing off while nothing arrives.
      if (_queues[c]!.length <= lowWatermark) {
        final n = (_empty[c] ?? 0) + 1;
        _empty[c] = n;
        _scheduleRetry(c, gen, Duration(
          milliseconds: min(maxBackoff.inMilliseconds, 5000 * (1 << min(n - 1, 10))),
        ));
      } else {
        _empty[c] = 0;
      }
    } else {
      _online = false;
      _lastError = error ?? 'لا توجد مصادر';
      final n = (_failures[c] ?? 0) + 1;
      _failures[c] = n;
      final delay = Duration(
        milliseconds: min(maxBackoff.inMilliseconds, 2000 * (1 << min(n - 1, 10))),
      );
      _scheduleRetry(c, gen, delay);
    }
    await _persist();
    _notify();
  }

  void _scheduleRetry(Category c, int gen, Duration delay) {
    if (_retryScheduled.contains(c)) return;
    _retryScheduled.add(c);
    _schedule(delay, () {
      _retryScheduled.remove(c);
      if (gen == _generation) _maybeRefill(c, force: true);
    });
  }

  void _ingest(Category c, List<Question> batch) {
    for (final q in batch) {
      if (q.category != c || q.validate().isNotEmpty) {
        _rejectedInvalid++;
        continue;
      }
      // Keep it in the offline reserve even if it cannot be used right now.
      _cached.putIfAbsent(q.id, () => q);
      final dup = _session.check(q) ?? _history.check(q);
      if (dup != null) {
        _rejectedDup++;
        continue;
      }
      _session.addQuestion(q);
      _queues[c]!.add(q);
    }
  }

  Future<void> _persist() async {
    if (_cached.length > maxCached) {
      final sorted = _cached.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final q in sorted.take(_cached.length - maxCached)) {
        _cached.remove(q.id);
      }
    }
    await cache.saveAll(_cached.values.toList());
  }

  /// Adds questions directly (e.g. bundled starter pack) to the reserve.
  void seed(List<Question> questions) {
    for (final q in questions) {
      if (q.validate().isEmpty) _cached.putIfAbsent(q.id, () => q);
    }
  }

  /// Forgets cross-session history (question bank "reset cycle").
  Future<void> clearHistory() async {
    _history.clear();
    await history.save(const []);
    _notify();
  }

  int get historySize => _history.length;

  void _notify() => onChange?.call();
}
