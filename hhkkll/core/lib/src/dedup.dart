import 'normalize.dart';
import 'question.dart';

/// Why a candidate question was rejected as a duplicate.
class DuplicateReason {
  const DuplicateReason(this.code, this.otherId, [this.score]);
  final String code;
  final String otherId;
  final double? score;
  @override
  String toString() => score == null
      ? '$code (vs $otherId)'
      : '$code ${score!.toStringAsFixed(2)} (vs $otherId)';
}

/// Thresholds for the similarity checks. Exposed so they can be tuned and
/// kept identical on the backend.
class DedupThresholds {
  const DedupThresholds({
    this.nearIdenticalText = 0.72,
    this.sameAnswerText = 0.30,
    this.auctionItemOverlap = 0.60,
  });

  /// Two questions whose wording is this similar are duplicates whatever the
  /// answer (catches light rephrasing).
  final double nearIdenticalText;

  /// Two questions with the same answer and at least this wording similarity
  /// test the same fact (catches rephrasing that keeps the key entities).
  final double sameAnswerText;

  /// Two auction questions whose valid-answer lists overlap this much are the
  /// same challenge.
  final double auctionItemOverlap;
}

/// Compact record of a question kept in history (no full text needed beyond
/// the trigram set).
class DedupEntry {
  DedupEntry({
    required this.id,
    required this.category,
    required this.textFp,
    required this.semanticFp,
    required this.answerKeys,
    required this.itemKeys,
    required this.trigrams,
    this.numbers = const {},
  });

  factory DedupEntry.of(Question q) => DedupEntry(
        id: q.id,
        category: q.category,
        textFp: q.textFingerprint,
        semanticFp: q.semanticFingerprint,
        answerKeys: q.answerKeys,
        itemKeys: q.itemKeys,
        trigrams: q.textTrigrams,
        numbers: numberTokens(q.fingerprintText),
      );

  final String id;
  final Category category;
  final String textFp;
  final String semanticFp;
  final Set<String> answerKeys;
  final Set<String> itemKeys;
  final Set<String> trigrams;
  final Set<String> numbers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'c': category.code,
        't': textFp,
        's': semanticFp,
        'a': answerKeys.toList(),
        'i': itemKeys.toList(),
        'g': trigrams.toList(),
        'n': numbers.toList(),
      };

  factory DedupEntry.fromJson(Map<String, dynamic> j) => DedupEntry(
        id: j['id'] as String,
        category: Category.fromCode(j['c'] as String),
        textFp: j['t'] as String,
        semanticFp: j['s'] as String,
        answerKeys: (j['a'] as List).cast<String>().toSet(),
        itemKeys: (j['i'] as List).cast<String>().toSet(),
        trigrams: (j['g'] as List).cast<String>().toSet(),
        numbers: (j['n'] as List? ?? const []).cast<String>().toSet(),
      );
}

/// Index of questions already used (or already queued) that rejects any new
/// question testing the same thing — exact repeats, re-worded repeats, the
/// same fact moved to another section, the same riddle subject, and auction
/// challenges with the same answer set.
class DedupIndex {
  DedupIndex({this.thresholds = const DedupThresholds()});

  final DedupThresholds thresholds;
  final Map<String, DedupEntry> _byId = {};
  final Map<String, String> _byTextFp = {};
  final Map<String, String> _bySemanticFp = {};

  int get length => _byId.length;
  Iterable<DedupEntry> get entries => _byId.values;
  bool containsId(String id) => _byId.containsKey(id);

  DuplicateReason? check(Question q) => checkEntry(DedupEntry.of(q));

  DuplicateReason? checkEntry(DedupEntry c) {
    if (_byId.containsKey(c.id)) return DuplicateReason('same-id', c.id);
    final t = _byTextFp[c.textFp];
    if (t != null) return DuplicateReason('same-wording', t);
    final s = _bySemanticFp[c.semanticFp];
    if (s != null) return DuplicateReason('same-fact', s);

    for (final e in _byId.values) {
      final sim = jaccard(c.trigrams, e.trigrams);
      final sameNumbers = c.numbers.length == e.numbers.length &&
          c.numbers.containsAll(e.numbers);
      if (sim >= thresholds.nearIdenticalText && sameNumbers) {
        return DuplicateReason('near-identical-wording', e.id, sim);
      }
      final sameAnswer = c.answerKeys.intersection(e.answerKeys).isNotEmpty;
      if (sameAnswer) {
        // A "who am I" riddle about the same person is the same riddle, however
        // the clues are worded.
        if (c.category == Category.whoAmI && e.category == Category.whoAmI) {
          return DuplicateReason('same-riddle-subject', e.id);
        }
        if (sim >= thresholds.sameAnswerText) {
          return DuplicateReason('same-answer-similar-question', e.id, sim);
        }
      }
      if (c.itemKeys.length >= 3 && e.itemKeys.length >= 3) {
        final overlap = jaccard(c.itemKeys, e.itemKeys);
        if (overlap >= thresholds.auctionItemOverlap) {
          return DuplicateReason('same-answer-set', e.id, overlap);
        }
      }
    }
    return null;
  }

  /// Adds the entry unconditionally (use [tryAdd] to check first).
  void add(DedupEntry e) {
    _byId[e.id] = e;
    _byTextFp[e.textFp] = e.id;
    _bySemanticFp[e.semanticFp] = e.id;
  }

  void addQuestion(Question q) => add(DedupEntry.of(q));

  /// Adds the question when it is not a duplicate. Returns the rejection
  /// reason, or null when added.
  DuplicateReason? tryAdd(Question q) {
    final e = DedupEntry.of(q);
    final r = checkEntry(e);
    if (r == null) add(e);
    return r;
  }

  void clear() {
    _byId.clear();
    _byTextFp.clear();
    _bySemanticFp.clear();
  }

  List<Map<String, dynamic>> toJson() =>
      _byId.values.map((e) => e.toJson()).toList();

  void loadJson(List<dynamic> list) {
    for (final m in list) {
      add(DedupEntry.fromJson((m as Map).cast()));
    }
  }
}
