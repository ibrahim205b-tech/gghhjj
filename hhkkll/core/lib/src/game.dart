import 'question.dart';

/// A competitor in a match.
class PlayerState {
  PlayerState({
    required this.id,
    required this.name,
    this.score = 0,
    this.strikes = 0,
    this.eliminated = false,
    this.correct = 0,
    this.wrong = 0,
    this.auctionsWon = 0,
    this.firstBuzzes = 0,
    this.passes = 0,
  });

  final String id;
  String name;
  int score;
  int strikes;
  bool eliminated;
  int correct;
  int wrong;
  int auctionsWon;
  int firstBuzzes;
  int passes;

  bool get active => !eliminated;

  factory PlayerState.fromJson(Map<String, dynamic> j) => PlayerState(
        id: j['id'] as String,
        name: j['name'] as String,
        score: j['score'] as int? ?? 0,
        strikes: j['strikes'] as int? ?? 0,
        eliminated: j['eliminated'] as bool? ?? false,
        correct: j['correct'] as int? ?? 0,
        wrong: j['wrong'] as int? ?? 0,
        auctionsWon: j['auctions_won'] as int? ?? 0,
        firstBuzzes: j['first_buzzes'] as int? ?? 0,
        passes: j['passes'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'score': score,
        'strikes': strikes,
        'eliminated': eliminated,
        'correct': correct,
        'wrong': wrong,
        'auctions_won': auctionsWon,
        'first_buzzes': firstBuzzes,
        'passes': passes,
      };
}

/// Referee-editable rules and point values.
class GameSettings {
  GameSettings({
    this.strikeLimit = 3,
    this.auctionSeconds = 30,
    this.auctionSuccessPoints = 30,
    this.auctionFailPenalty = 20,
    this.auctionStrikeOnFail = true,
    this.wdykPoints = 10,
    this.wdykSeconds = 20,
    this.buzzerPoints = 15,
    this.buzzerWrongPenalty = 5,
    this.buzzerCountdown = 3,
    this.buzzerAnswerSeconds = 10,
    List<int>? whoAmIPoints,
    this.whoAmIStrikeOnWrong = false,
  }) : whoAmIPoints = whoAmIPoints ?? [50, 40, 30, 20, 10];

  int strikeLimit;
  int auctionSeconds;
  int auctionSuccessPoints;
  int auctionFailPenalty;
  bool auctionStrikeOnFail;
  int wdykPoints;
  int wdykSeconds;
  int buzzerPoints;
  int buzzerWrongPenalty;
  int buzzerCountdown;
  int buzzerAnswerSeconds;

  /// Points for a correct "who am I" guess after 1, 2, 3, ... clues.
  List<int> whoAmIPoints;
  bool whoAmIStrikeOnWrong;

  int whoAmIPointsFor(int cluesRevealed) {
    if (whoAmIPoints.isEmpty) return 0;
    final i = (cluesRevealed - 1).clamp(0, whoAmIPoints.length - 1);
    return whoAmIPoints[i];
  }

  factory GameSettings.fromJson(Map<String, dynamic> j) => GameSettings(
        strikeLimit: j['strike_limit'] as int? ?? 3,
        auctionSeconds: j['auction_seconds'] as int? ?? 30,
        auctionSuccessPoints: j['auction_success_points'] as int? ?? 30,
        auctionFailPenalty: j['auction_fail_penalty'] as int? ?? 20,
        auctionStrikeOnFail: j['auction_strike_on_fail'] as bool? ?? true,
        wdykPoints: j['wdyk_points'] as int? ?? 10,
        wdykSeconds: j['wdyk_seconds'] as int? ?? 20,
        buzzerPoints: j['buzzer_points'] as int? ?? 15,
        buzzerWrongPenalty: j['buzzer_wrong_penalty'] as int? ?? 5,
        buzzerCountdown: j['buzzer_countdown'] as int? ?? 3,
        buzzerAnswerSeconds: j['buzzer_answer_seconds'] as int? ?? 10,
        whoAmIPoints: (j['who_am_i_points'] as List?)?.cast<int>(),
        whoAmIStrikeOnWrong: j['who_am_i_strike_on_wrong'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'strike_limit': strikeLimit,
        'auction_seconds': auctionSeconds,
        'auction_success_points': auctionSuccessPoints,
        'auction_fail_penalty': auctionFailPenalty,
        'auction_strike_on_fail': auctionStrikeOnFail,
        'wdyk_points': wdykPoints,
        'wdyk_seconds': wdykSeconds,
        'buzzer_points': buzzerPoints,
        'buzzer_wrong_penalty': buzzerWrongPenalty,
        'buzzer_countdown': buzzerCountdown,
        'buzzer_answer_seconds': buzzerAnswerSeconds,
        'who_am_i_points': whoAmIPoints,
        'who_am_i_strike_on_wrong': whoAmIStrikeOnWrong,
      };

  GameSettings copy() => GameSettings.fromJson(toJson());
}

class GameEvent {
  GameEvent(this.at, this.type, this.text, {this.playerId, this.questionId});
  final DateTime at;
  final String type;
  final String text;
  final String? playerId;
  final String? questionId;

  factory GameEvent.fromJson(Map<String, dynamic> j) => GameEvent(
        DateTime.parse(j['at'] as String),
        j['type'] as String,
        j['text'] as String,
        playerId: j['player'] as String?,
        questionId: j['question'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'type': type,
        'text': text,
        if (playerId != null) 'player': playerId,
        if (questionId != null) 'question': questionId,
      };
}

class UsedQuestion {
  UsedQuestion(this.id, this.category, this.at, this.text, this.answer);
  final String id;
  final Category category;
  final DateTime at;
  final String text;
  final String answer;

  factory UsedQuestion.fromJson(Map<String, dynamic> j) => UsedQuestion(
        j['id'] as String,
        Category.fromCode(j['category'] as String),
        DateTime.parse(j['at'] as String),
        j['text'] as String? ?? '',
        j['answer'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.code,
        'at': at.toUtc().toIso8601String(),
        'text': text,
        'answer': answer,
      };
}

/// Result of a strike being added.
class StrikeResult {
  const StrikeResult(this.strikes, this.eliminatedNow);
  final int strikes;
  final bool eliminatedNow;
}

/// A whole match: players, scores, rules, history of used questions and an
/// event log. Every mutation goes through a method so it is logged and can be
/// persisted / synchronised.
class GameSession {
  GameSession({
    required this.id,
    required this.players,
    required this.settings,
    DateTime? createdAt,
    this.finishedAt,
    List<UsedQuestion>? used,
    List<GameEvent>? log,
    this.roundsPlayed = 0,
    this.activeRound,
    DateTime Function()? clock,
  })  : createdAt = createdAt ?? DateTime.now(),
        used = used ?? [],
        log = log ?? [],
        _clock = clock ?? DateTime.now;

  final String id;
  final List<PlayerState> players;
  GameSettings settings;
  final DateTime createdAt;
  DateTime? finishedAt;
  final List<UsedQuestion> used;
  final List<GameEvent> log;
  int roundsPlayed;

  /// Serialised state of the round in progress (for resume after restart).
  Map<String, dynamic>? activeRound;
  final DateTime Function() _clock;

  bool get finished => finishedAt != null;

  PlayerState player(String id) => players.firstWhere(
        (p) => p.id == id,
        orElse: () => throw ArgumentError('unknown player $id'),
      );

  List<PlayerState> get activePlayers =>
      players.where((p) => p.active).toList();

  /// Ranking: score desc, then correct answers desc, then fewer strikes.
  List<PlayerState> get ranking {
    final l = [...players];
    l.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final c = b.correct.compareTo(a.correct);
      if (c != 0) return c;
      return a.strikes.compareTo(b.strikes);
    });
    return l;
  }

  bool isUsed(String questionId) => used.any((u) => u.id == questionId);

  void _log(String type, String text, {String? playerId, String? questionId}) {
    log.add(GameEvent(_clock(), type, text,
        playerId: playerId, questionId: questionId));
  }

  void markUsed(Question q) {
    if (isUsed(q.id)) return;
    used.add(UsedQuestion(q.id, q.category, _clock(), q.text, q.answer));
    _log('question', '${q.category.arabic}: ${q.text}', questionId: q.id);
  }

  void addPoints(String playerId, int points, {String reason = ''}) {
    final p = player(playerId);
    p.score += points;
    _log(points >= 0 ? 'points+' : 'points-',
        '${p.name} ${points >= 0 ? '+' : ''}$points $reason'.trim(),
        playerId: playerId);
  }

  void recordCorrect(String playerId, int points, {String reason = ''}) {
    player(playerId).correct++;
    addPoints(playerId, points, reason: reason);
  }

  void recordWrong(String playerId) {
    player(playerId).wrong++;
  }

  StrikeResult addStrike(String playerId, {String reason = ''}) {
    final p = player(playerId);
    if (p.eliminated) return StrikeResult(p.strikes, false);
    p.strikes++;
    _log('strike', '${p.name} ✗ ${p.strikes}/${settings.strikeLimit} $reason'.trim(),
        playerId: playerId);
    if (p.strikes >= settings.strikeLimit) {
      p.eliminated = true;
      _log('eliminated', '${p.name} أُقصي من المنافسة', playerId: playerId);
      return StrikeResult(p.strikes, true);
    }
    return StrikeResult(p.strikes, false);
  }

  void removeStrike(String playerId) {
    final p = player(playerId);
    if (p.strikes == 0) return;
    p.strikes--;
    _log('strike-removed', '${p.name} أزيل خطأ (${p.strikes})',
        playerId: playerId);
  }

  void eliminate(String playerId) {
    final p = player(playerId);
    if (p.eliminated) return;
    p.eliminated = true;
    _log('eliminated', '${p.name} أُقصي بقرار الحكم', playerId: playerId);
  }

  /// Brings a player back. Their strikes drop below the limit so the next
  /// mistake does not eliminate them instantly.
  void restore(String playerId) {
    final p = player(playerId);
    if (!p.eliminated) return;
    p.eliminated = false;
    if (p.strikes >= settings.strikeLimit) p.strikes = settings.strikeLimit - 1;
    _log('restored', '${p.name} عاد إلى المنافسة', playerId: playerId);
  }

  void renamePlayer(String playerId, String name) {
    player(playerId).name = name;
  }

  void finish() {
    finishedAt ??= _clock();
    activeRound = null;
    _log('finished', 'انتهت المنافسة');
  }

  factory GameSession.fromJson(Map<String, dynamic> j) => GameSession(
        id: j['id'] as String,
        players: (j['players'] as List)
            .map((e) => PlayerState.fromJson((e as Map).cast()))
            .toList(),
        settings: GameSettings.fromJson((j['settings'] as Map).cast()),
        createdAt: DateTime.parse(j['created_at'] as String),
        finishedAt: j['finished_at'] == null
            ? null
            : DateTime.parse(j['finished_at'] as String),
        used: (j['used'] as List? ?? const [])
            .map((e) => UsedQuestion.fromJson((e as Map).cast()))
            .toList(),
        log: (j['log'] as List? ?? const [])
            .map((e) => GameEvent.fromJson((e as Map).cast()))
            .toList(),
        roundsPlayed: j['rounds_played'] as int? ?? 0,
        activeRound: (j['active_round'] as Map?)?.cast<String, dynamic>(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'players': players.map((p) => p.toJson()).toList(),
        'settings': settings.toJson(),
        'created_at': createdAt.toUtc().toIso8601String(),
        if (finishedAt != null)
          'finished_at': finishedAt!.toUtc().toIso8601String(),
        'used': used.map((u) => u.toJson()).toList(),
        'log': log.map((e) => e.toJson()).toList(),
        'rounds_played': roundsPlayed,
        if (activeRound != null) 'active_round': activeRound,
      };
}
