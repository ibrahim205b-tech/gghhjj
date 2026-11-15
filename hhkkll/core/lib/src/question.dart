import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'normalize.dart';

/// The four game sections.
enum Category {
  auction('auction', 'المزاد', 'AUCTION'),
  whatDoYouKnow('wdyk', 'ماذا تعرف؟', 'WHAT DO YOU KNOW'),
  buzzer('buzzer', 'الجرس', 'BUZZER'),
  whoAmI('whoami', 'من أنا؟', 'WHO AM I');

  const Category(this.code, this.arabic, this.english);
  final String code;
  final String arabic;
  final String english;

  static Category fromCode(String code) => Category.values.firstWhere(
        (c) => c.code == code,
        orElse: () => throw FormatException('unknown category "$code"'),
      );
}

enum Difficulty {
  hard('hard', 'صعب'),
  expert('expert', 'خبير'),
  veryExpert('very_expert', 'خبير جداً'),
  historic('historic', 'تاريخي'),
  impossible('impossible', 'مستحيل');

  const Difficulty(this.code, this.arabic);
  final String code;
  final String arabic;

  static Difficulty fromCode(String code) => Difficulty.values.firstWhere(
        (c) => c.code == code,
        orElse: () => throw FormatException('unknown difficulty "$code"'),
      );
}

class Source {
  const Source({required this.title, required this.url});
  final String title;
  final String url;

  factory Source.fromJson(Map<String, dynamic> j) =>
      Source(title: j['title'] as String? ?? '', url: j['url'] as String);
  Map<String, dynamic> toJson() => {'title': title, 'url': url};
}

/// How a question's facts were checked.
///
/// * `verified` — an independent AI verification pass confirmed the facts
///   against web pages it actually retrieved (URLs recorded in [sources]).
/// * `curated` — written by hand for the offline starter pack, with a
///   reference link the referee can open. Not machine-verified.
class Verification {
  const Verification({
    required this.status,
    required this.method,
    this.model,
    this.checkedAt,
    this.notes,
  });
  final String status;
  final String method;
  final String? model;
  final DateTime? checkedAt;
  final String? notes;

  bool get isVerified => status == 'verified';

  factory Verification.fromJson(Map<String, dynamic> j) => Verification(
        status: j['status'] as String,
        method: j['method'] as String? ?? '',
        model: j['model'] as String?,
        checkedAt: j['checked_at'] == null
            ? null
            : DateTime.parse(j['checked_at'] as String),
        notes: j['notes'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'status': status,
        'method': method,
        if (model != null) 'model': model,
        if (checkedAt != null) 'checked_at': checkedAt!.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
      };
}

/// One valid answer for an auction question (e.g. a player name), with
/// spelling variants the referee may hear.
class AuctionItem {
  const AuctionItem({required this.name, this.aliases = const []});
  final String name;
  final List<String> aliases;

  factory AuctionItem.fromJson(Map<String, dynamic> j) => AuctionItem(
        name: j['name'] as String,
        aliases: (j['aliases'] as List? ?? const []).cast<String>(),
      );
  Map<String, dynamic> toJson() => {'name': name, 'aliases': aliases};

  Set<String> get keys => {name, ...aliases}.map(normalizeAnswer).toSet();
}

class Question {
  Question({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.text,
    required this.answer,
    this.acceptedAnswers = const [],
    this.items = const [],
    this.itemsExhaustive = false,
    this.clues = const [],
    this.topic = '',
    this.semanticKey = '',
    required this.sources,
    this.factAsOf,
    required this.createdAt,
    required this.verification,
    this.origin = 'seed',
  });

  final String id;
  final Category category;
  final Difficulty difficulty;

  /// The question shown to players (Arabic).
  final String text;

  /// The main correct answer shown to the referee.
  final String answer;

  /// Spelling variants / alternative correct answers.
  final List<String> acceptedAnswers;

  /// Auction only: the reference list of valid answers.
  final List<AuctionItem> items;

  /// Auction only: true when [items] is the complete list of valid answers.
  final bool itemsExhaustive;

  /// Who am I only: clues ordered from hardest to easiest.
  final List<String> clues;

  final String topic;

  /// Canonical, language-neutral description of the underlying fact, e.g.
  /// `euro-2000-final|golden-goal-scorer`. Two questions with the same key
  /// test the same fact and are duplicates even if worded differently.
  final String semanticKey;

  final List<Source> sources;

  /// Date the facts were true for (important for records / transfers).
  final String? factAsOf;
  final DateTime createdAt;
  final Verification verification;

  /// `seed` (bundled), `server` (live backend) or `feed` (published feed).
  final String origin;

  /// The text that identifies the challenge: the clues for "who am I"
  /// (whose visible question is always the same), the question otherwise.
  String get fingerprintText =>
      category == Category.whoAmI && clues.isNotEmpty ? clues.join(' ') : text;

  /// Fingerprint of the wording: hash of the sorted unique content tokens.
  late final String textFingerprint = _sha1(
    'txt:${(contentTokens(fingerprintText).toSet().toList()..sort()).join(' ')}',
  );

  /// Fingerprint of the meaning: the canonical fact key when available,
  /// otherwise category-independent answer identity.
  late final String semanticFingerprint = _sha1(
    semanticKey.trim().isNotEmpty
        ? 'sem:${normalizeText(semanticKey).replaceAll(' ', '-')}'
        : 'ans:${answerKeys.toList()..sort()}|${(contentTokens(fingerprintText).toSet().toList()..sort()).take(6).join(',')}',
  );

  /// Normalised identities of the answer(s). An auction's answer is only a
  /// count; its identity is the item list ([itemKeys]).
  late final Set<String> answerKeys = category == Category.auction
      ? const <String>{}
      : {
          answer,
          ...acceptedAnswers,
        }.map(normalizeAnswer).where((s) => s.isNotEmpty).toSet();

  /// Normalised identities of the auction items (each item = its main name).
  late final Set<String> itemKeys =
      items.map((i) => normalizeAnswer(i.name)).toSet();

  late final Set<String> textTrigrams = trigrams(fingerprintText);

  /// Points the referee to the strongest reference for this question.
  Source? get primarySource => sources.isEmpty ? null : sources.first;

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id'] as String,
        category: Category.fromCode(j['category'] as String),
        difficulty: Difficulty.fromCode(j['difficulty'] as String),
        text: j['question'] as String,
        answer: j['answer'] as String,
        acceptedAnswers:
            (j['accepted_answers'] as List? ?? const []).cast<String>(),
        items: (j['items'] as List? ?? const [])
            .map((e) => AuctionItem.fromJson((e as Map).cast()))
            .toList(),
        itemsExhaustive: j['items_exhaustive'] as bool? ?? false,
        clues: (j['clues'] as List? ?? const []).cast<String>(),
        topic: j['topic'] as String? ?? '',
        semanticKey: j['semantic_key'] as String? ?? '',
        sources: (j['sources'] as List? ?? const [])
            .map((e) => Source.fromJson((e as Map).cast()))
            .toList(),
        factAsOf: j['fact_as_of'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        verification:
            Verification.fromJson((j['verification'] as Map).cast()),
        origin: j['origin'] as String? ?? 'seed',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.code,
        'difficulty': difficulty.code,
        'question': text,
        'answer': answer,
        'accepted_answers': acceptedAnswers,
        if (items.isNotEmpty) 'items': items.map((e) => e.toJson()).toList(),
        if (items.isNotEmpty) 'items_exhaustive': itemsExhaustive,
        if (clues.isNotEmpty) 'clues': clues,
        'topic': topic,
        'semantic_key': semanticKey,
        'sources': sources.map((e) => e.toJson()).toList(),
        if (factAsOf != null) 'fact_as_of': factAsOf,
        'created_at': createdAt.toUtc().toIso8601String(),
        'verification': verification.toJson(),
        'origin': origin,
        'text_fp': textFingerprint,
        'semantic_fp': semanticFingerprint,
      };

  /// Structural validation. Returns a list of problems (empty = valid).
  List<String> validate() {
    final p = <String>[];
    if (id.trim().isEmpty) p.add('empty id');
    if (text.trim().length < 8 && category != Category.whoAmI) {
      p.add('question text too short');
    }
    if (answer.trim().isEmpty) p.add('empty answer');
    if (sources.isEmpty) p.add('no source');
    for (final s in sources) {
      final u = Uri.tryParse(s.url);
      if (u == null || !(u.isScheme('https') || u.isScheme('http')) ||
          u.host.isEmpty) {
        p.add('bad source url "${s.url}"');
      }
    }
    switch (category) {
      case Category.auction:
        if (items.length < 3) p.add('auction needs at least 3 reference items');
      case Category.whoAmI:
        if (clues.length < 3 || clues.length > 5) {
          p.add('who-am-i needs 3 to 5 clues');
        }
      case Category.whatDoYouKnow:
      case Category.buzzer:
        break;
    }
    return p;
  }

  static String _sha1(String s) =>
      sha1.convert(utf8.encode(s)).toString().substring(0, 20);
}
