import 'game.dart';

/// Base class of the four section state machines. A round never touches the
/// UI: the app calls the methods and reacts to the returned results (sounds,
/// animations). All rounds are serialisable so an interrupted match resumes
/// exactly where it stopped.
abstract class Round {
  Round(this.questionId);
  final String questionId;
  String get kind;
  bool get done;
  Map<String, dynamic> toJson();

  static Round fromJson(Map<String, dynamic> j) {
    switch (j['kind']) {
      case AuctionRound.kindName:
        return AuctionRound.fromJson(j);
      case WdykRound.kindName:
        return WdykRound.fromJson(j);
      case BuzzerRound.kindName:
        return BuzzerRound.fromJson(j);
      case WhoAmIRound.kindName:
        return WhoAmIRound.fromJson(j);
    }
    throw FormatException('unknown round kind ${j['kind']}');
  }
}

class RoundError implements Exception {
  RoundError(this.message);
  final String message;
  @override
  String toString() => 'RoundError: $message';
}

// ---------------------------------------------------------------------------
// AUCTION
// ---------------------------------------------------------------------------

class Bid {
  const Bid(this.playerId, this.amount);
  final String playerId;
  final int amount;
}

enum AuctionPhase { bidding, answering, done }

class AuctionOutcome {
  const AuctionOutcome({
    required this.success,
    required this.winnerId,
    required this.target,
    required this.achieved,
    required this.points,
    this.strike,
  });
  final bool success;
  final String winnerId;
  final int target;
  final int achieved;
  final int points;
  final StrikeResult? strike;
}

class AuctionRound extends Round {
  AuctionRound({
    required String questionId,
    required this.participants,
    this.maxBid,
  }) : super(questionId);

  static const kindName = 'auction';
  @override
  String get kind => kindName;

  final List<String> participants;

  /// Upper bound for bids (size of an exhaustive answer list), if known.
  final int? maxBid;
  final Set<String> withdrawn = {};
  final List<Bid> bids = [];
  AuctionPhase phase = AuctionPhase.bidding;

  /// Answering phase: indices of reference items the winner named correctly.
  final Set<int> namedItems = {};

  /// Correct names the referee accepted that are not in the reference list.
  int extraCorrect = 0;
  int wrongNames = 0;
  AuctionOutcome? outcome;

  @override
  bool get done => phase == AuctionPhase.done;

  int get highestBid => bids.isEmpty ? 0 : bids.last.amount;
  String? get highestBidder => bids.isEmpty ? null : bids.last.playerId;
  List<String> get remainingBidders =>
      participants.where((p) => !withdrawn.contains(p)).toList();

  /// True when everybody except the highest bidder has withdrawn.
  bool get decided =>
      highestBidder != null &&
      remainingBidders.length == 1 &&
      remainingBidders.first == highestBidder;

  int get correctCount => namedItems.length + extraCorrect;
  bool get reachedTarget => correctCount >= highestBid && highestBid > 0;

  void bid(String playerId, int amount) {
    if (phase != AuctionPhase.bidding) throw RoundError('المزايدة مغلقة');
    if (!participants.contains(playerId)) throw RoundError('لاعب غير مشارك');
    if (withdrawn.contains(playerId)) throw RoundError('اللاعب انسحب');
    if (amount <= highestBid) {
      throw RoundError('يجب أن تتجاوز المزايدة $highestBid');
    }
    if (maxBid != null && amount > maxBid!) {
      throw RoundError('الحد الأعلى للمزايدة $maxBid');
    }
    bids.add(Bid(playerId, amount));
  }

  /// Referee correction: removes the last bid.
  void undoBid() {
    if (phase != AuctionPhase.bidding || bids.isEmpty) return;
    bids.removeLast();
  }

  void withdraw(String playerId) {
    if (phase != AuctionPhase.bidding) return;
    if (playerId == highestBidder) {
      throw RoundError('صاحب أعلى مزايدة لا يستطيع الانسحاب');
    }
    withdrawn.add(playerId);
  }

  void rejoin(String playerId) {
    if (phase != AuctionPhase.bidding) return;
    withdrawn.remove(playerId);
  }

  /// Closes bidding and gives the highest bidder the floor.
  void startAnswering() {
    if (phase != AuctionPhase.bidding) return;
    if (highestBidder == null) throw RoundError('لا توجد مزايدات');
    phase = AuctionPhase.answering;
  }

  void toggleItem(int index) {
    if (phase != AuctionPhase.answering) return;
    if (!namedItems.remove(index)) namedItems.add(index);
  }

  void addExtraCorrect() {
    if (phase == AuctionPhase.answering) extraCorrect++;
  }

  void removeExtraCorrect() {
    if (phase == AuctionPhase.answering && extraCorrect > 0) extraCorrect--;
  }

  void addWrongName() {
    if (phase == AuctionPhase.answering) wrongNames++;
  }

  /// Ends the auction and applies points / penalty to the winner.
  AuctionOutcome resolve(GameSession s) {
    if (phase != AuctionPhase.answering) {
      throw RoundError('لم تبدأ مرحلة الإجابة');
    }
    final winner = highestBidder!;
    final success = reachedTarget;
    StrikeResult? strike;
    int pts;
    if (success) {
      pts = s.settings.auctionSuccessPoints;
      s.player(winner).auctionsWon++;
      s.recordCorrect(winner, pts, reason: 'نجح في المزاد ($correctCount/$highestBid)');
    } else {
      pts = -s.settings.auctionFailPenalty;
      s.recordWrong(winner);
      if (pts != 0) {
        s.addPoints(winner, pts, reason: 'فشل في المزاد ($correctCount/$highestBid)');
      }
      if (s.settings.auctionStrikeOnFail) {
        strike = s.addStrike(winner, reason: 'المزاد');
      }
    }
    phase = AuctionPhase.done;
    return outcome = AuctionOutcome(
      success: success,
      winnerId: winner,
      target: highestBid,
      achieved: correctCount,
      points: pts,
      strike: strike,
    );
  }

  /// Ends without scoring (e.g. question cancelled by the referee).
  void cancel() => phase = AuctionPhase.done;

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'question': questionId,
        'participants': participants,
        if (maxBid != null) 'max_bid': maxBid,
        'withdrawn': withdrawn.toList(),
        'bids': [
          for (final b in bids) {'p': b.playerId, 'a': b.amount},
        ],
        'phase': phase.name,
        'named': namedItems.toList(),
        'extra': extraCorrect,
        'wrong': wrongNames,
      };

  factory AuctionRound.fromJson(Map<String, dynamic> j) {
    final r = AuctionRound(
      questionId: j['question'] as String,
      participants: (j['participants'] as List).cast<String>(),
      maxBid: j['max_bid'] as int?,
    );
    r.withdrawn.addAll((j['withdrawn'] as List).cast<String>());
    for (final b in j['bids'] as List) {
      final m = (b as Map).cast<String, dynamic>();
      r.bids.add(Bid(m['p'] as String, m['a'] as int));
    }
    r.phase = AuctionPhase.values.byName(j['phase'] as String);
    r.namedItems.addAll((j['named'] as List).cast<int>());
    r.extraCorrect = j['extra'] as int? ?? 0;
    r.wrongNames = j['wrong'] as int? ?? 0;
    return r;
  }
}

// ---------------------------------------------------------------------------
// WHAT DO YOU KNOW — turn order, PASS and STRIKE
// ---------------------------------------------------------------------------

enum TurnResult { correct, wrong, passed, eliminated, exhausted }

class TurnOutcome {
  const TurnOutcome(this.result, this.playerId, {this.strike, this.next});
  final TurnResult result;
  final String playerId;
  final StrikeResult? strike;

  /// Player who now has the floor (null when the round ended).
  final String? next;
}

class WdykRound extends Round {
  WdykRound({required String questionId, required this.order})
      : super(questionId);

  static const kindName = 'wdyk';
  @override
  String get kind => kindName;

  /// Turn order chosen by the referee (first = starting player).
  final List<String> order;
  int currentIndex = 0;
  final Set<String> tried = {};
  final Set<String> passedBy = {};
  String? winnerId;
  bool _done = false;

  @override
  bool get done => _done;

  /// Builds the turn order from the active players, starting at [starter]
  /// and following the roster order.
  factory WdykRound.start(GameSession s, String questionId, String starter) {
    final ids = s.activePlayers.map((p) => p.id).toList();
    final i = ids.indexOf(starter);
    if (i < 0) throw RoundError('اللاعب غير متاح');
    return WdykRound(
      questionId: questionId,
      order: [...ids.sublist(i), ...ids.sublist(0, i)],
    );
  }

  String? get current => _done ? null : order[currentIndex];

  /// Referee override: give the floor to a specific player.
  void setCurrent(String playerId) {
    final i = order.indexOf(playerId);
    if (i < 0 || _done) return;
    currentIndex = i;
    tried.remove(playerId);
    passedBy.remove(playerId);
  }

  String? _advance(GameSession s) {
    for (var step = 1; step <= order.length; step++) {
      final i = (currentIndex + step) % order.length;
      final id = order[i];
      if (s.player(id).active && !tried.contains(id)) {
        currentIndex = i;
        return id;
      }
    }
    _done = true;
    return null;
  }

  TurnOutcome correct(GameSession s) {
    final p = current ?? (throw RoundError('انتهى السؤال'));
    s.recordCorrect(p, s.settings.wdykPoints, reason: 'ماذا تعرف؟');
    winnerId = p;
    _done = true;
    return TurnOutcome(TurnResult.correct, p);
  }

  TurnOutcome wrong(GameSession s) {
    final p = current ?? (throw RoundError('انتهى السؤال'));
    s.recordWrong(p);
    final strike = s.addStrike(p, reason: 'ماذا تعرف؟');
    tried.add(p);
    final next = _advance(s);
    return TurnOutcome(
      strike.eliminatedNow
          ? TurnResult.eliminated
          : (next == null ? TurnResult.exhausted : TurnResult.wrong),
      p,
      strike: strike,
      next: next,
    );
  }

  TurnOutcome pass(GameSession s) {
    final p = current ?? (throw RoundError('انتهى السؤال'));
    s.player(p).passes++;
    tried.add(p);
    passedBy.add(p);
    final next = _advance(s);
    return TurnOutcome(
      next == null ? TurnResult.exhausted : TurnResult.passed,
      p,
      next: next,
    );
  }

  /// Referee closes the question (answer revealed, nobody scores).
  void close() => _done = true;

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'question': questionId,
        'order': order,
        'index': currentIndex,
        'tried': tried.toList(),
        'passed': passedBy.toList(),
        if (winnerId != null) 'winner': winnerId,
        'done': _done,
      };

  factory WdykRound.fromJson(Map<String, dynamic> j) {
    final r = WdykRound(
      questionId: j['question'] as String,
      order: (j['order'] as List).cast<String>(),
    );
    r.currentIndex = j['index'] as int;
    r.tried.addAll((j['tried'] as List).cast<String>());
    r.passedBy.addAll((j['passed'] as List? ?? const []).cast<String>());
    r.winnerId = j['winner'] as String?;
    r._done = j['done'] as bool? ?? false;
    return r;
  }
}

// ---------------------------------------------------------------------------
// BUZZER — first press wins, everyone else is locked out instantly
// ---------------------------------------------------------------------------

enum BuzzerPhase { ready, countdown, open, locked, judged, done }

class BuzzResult {
  const BuzzResult(this.accepted, this.playerId, this.reactionMs);
  final bool accepted;
  final String playerId;
  final int reactionMs;
}

class BuzzerRound extends Round {
  BuzzerRound({required String questionId}) : super(questionId);

  static const kindName = 'buzzer';
  @override
  String get kind => kindName;

  BuzzerPhase phase = BuzzerPhase.ready;
  final Set<String> lockedOut = {};
  String? lockedBy;
  String? winnerId;
  int _openedAtMicros = 0;

  /// Every press attempt (accepted or not) with its reaction time, so the
  /// referee can see who was second, third...
  final List<BuzzResult> presses = [];

  @override
  bool get done => phase == BuzzerPhase.done;

  void startCountdown() {
    if (phase == BuzzerPhase.ready) phase = BuzzerPhase.countdown;
  }

  /// Opens the buzzers. [nowMicros] comes from a monotonic clock.
  void open(int nowMicros) {
    if (phase == BuzzerPhase.done) return;
    phase = BuzzerPhase.open;
    lockedBy = null;
    _openedAtMicros = nowMicros;
  }

  /// Registers a press. Only the first eligible press while open is accepted;
  /// the buzzers lock in the same synchronous call so a second press — even
  /// in the same frame — is rejected.
  BuzzResult press(GameSession s, String playerId, int nowMicros) {
    final ms = ((nowMicros - _openedAtMicros) / 1000).round();
    final eligible = phase == BuzzerPhase.open &&
        s.player(playerId).active &&
        !lockedOut.contains(playerId);
    final r = BuzzResult(eligible, playerId, ms);
    presses.add(r);
    if (eligible) {
      phase = BuzzerPhase.locked;
      lockedBy = playerId;
      s.player(playerId).firstBuzzes++;
    }
    return r;
  }

  TurnOutcome correct(GameSession s) {
    final p = lockedBy ?? (throw RoundError('لم يضغط أحد'));
    s.recordCorrect(p, s.settings.buzzerPoints, reason: 'الجرس');
    winnerId = p;
    phase = BuzzerPhase.done;
    return TurnOutcome(TurnResult.correct, p);
  }

  TurnOutcome wrong(GameSession s) {
    final p = lockedBy ?? (throw RoundError('لم يضغط أحد'));
    s.recordWrong(p);
    if (s.settings.buzzerWrongPenalty > 0) {
      s.addPoints(p, -s.settings.buzzerWrongPenalty, reason: 'الجرس');
    }
    final strike = s.addStrike(p, reason: 'الجرس');
    lockedOut.add(p);
    phase = eligiblePlayers(s).isEmpty ? BuzzerPhase.done : BuzzerPhase.judged;
    return TurnOutcome(
      strike.eliminatedNow ? TurnResult.eliminated : TurnResult.wrong,
      p,
      strike: strike,
    );
  }

  List<String> eligiblePlayers(GameSession s) => s.activePlayers
      .map((p) => p.id)
      .where((id) => !lockedOut.contains(id))
      .toList();

  /// After a wrong answer the referee re-opens the buzzers for the others.
  void reopen(int nowMicros) {
    if (phase == BuzzerPhase.judged) open(nowMicros);
  }

  void close() => phase = BuzzerPhase.done;

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'question': questionId,
        // An in-flight countdown/open state cannot survive a restart; resume
        // at "ready" (or "judged" if someone already answered wrong).
        'phase': switch (phase) {
          BuzzerPhase.countdown || BuzzerPhase.open || BuzzerPhase.locked =>
            lockedOut.isEmpty ? BuzzerPhase.ready.name : BuzzerPhase.judged.name,
          _ => phase.name,
        },
        'locked_out': lockedOut.toList(),
        if (winnerId != null) 'winner': winnerId,
      };

  factory BuzzerRound.fromJson(Map<String, dynamic> j) {
    final r = BuzzerRound(questionId: j['question'] as String);
    r.phase = BuzzerPhase.values.byName(j['phase'] as String);
    r.lockedOut.addAll((j['locked_out'] as List).cast<String>());
    r.winnerId = j['winner'] as String?;
    return r;
  }
}

// ---------------------------------------------------------------------------
// WHO AM I — progressive clues, earlier = more points
// ---------------------------------------------------------------------------

class WhoAmIRound extends Round {
  WhoAmIRound({required String questionId, required this.clueCount})
      : super(questionId);

  static const kindName = 'whoami';
  @override
  String get kind => kindName;

  final int clueCount;
  int revealed = 0;

  /// Players who guessed wrong on the current clue; they may try again after
  /// the next clue is revealed.
  final Set<String> lockedForClue = {};
  String? winnerId;
  int? pointsAwarded;
  bool _done = false;

  @override
  bool get done => _done;

  bool get canReveal => !_done && revealed < clueCount;

  void revealNext() {
    if (!canReveal) return;
    revealed++;
    lockedForClue.clear();
  }

  int currentPoints(GameSession s) => s.settings.whoAmIPointsFor(revealed);

  bool canAttempt(GameSession s, String playerId) =>
      !_done &&
      revealed > 0 &&
      s.player(playerId).active &&
      !lockedForClue.contains(playerId);

  TurnOutcome correct(GameSession s, String playerId) {
    if (!canAttempt(s, playerId)) throw RoundError('لا يمكن لهذا اللاعب الإجابة الآن');
    final pts = currentPoints(s);
    s.recordCorrect(playerId, pts, reason: 'من أنا؟ (تلميح $revealed)');
    winnerId = playerId;
    pointsAwarded = pts;
    _done = true;
    return TurnOutcome(TurnResult.correct, playerId);
  }

  TurnOutcome wrong(GameSession s, String playerId) {
    if (!canAttempt(s, playerId)) throw RoundError('لا يمكن لهذا اللاعب الإجابة الآن');
    s.recordWrong(playerId);
    lockedForClue.add(playerId);
    StrikeResult? strike;
    if (s.settings.whoAmIStrikeOnWrong) {
      strike = s.addStrike(playerId, reason: 'من أنا؟');
    }
    return TurnOutcome(
      strike?.eliminatedNow == true ? TurnResult.eliminated : TurnResult.wrong,
      playerId,
      strike: strike,
    );
  }

  void close() => _done = true;

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'question': questionId,
        'clues': clueCount,
        'revealed': revealed,
        'locked': lockedForClue.toList(),
        if (winnerId != null) 'winner': winnerId,
        if (pointsAwarded != null) 'points': pointsAwarded,
        'done': _done,
      };

  factory WhoAmIRound.fromJson(Map<String, dynamic> j) {
    final r = WhoAmIRound(
      questionId: j['question'] as String,
      clueCount: j['clues'] as int,
    );
    r.revealed = j['revealed'] as int;
    r.lockedForClue.addAll((j['locked'] as List).cast<String>());
    r.winnerId = j['winner'] as String?;
    r.pointsAwarded = j['points'] as int?;
    r._done = j['done'] as bool? ?? false;
    return r;
  }
}
