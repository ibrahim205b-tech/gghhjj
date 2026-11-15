import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import 'sound.dart';
import 'sources.dart';
import 'storage.dart';

/// Default location of the feed published by `.github/workflows/hhkkll-questions.yml`.
const defaultFeedUrl =
    'https://raw.githubusercontent.com/ibrahim205b-tech/gghhjj/hhkkll-feed/feed';

class AppSettings {
  AppSettings({
    this.volume = 0.9,
    this.muted = false,
    this.showIntro = true,
    this.serverUrl = '',
    this.feedUrl = defaultFeedUrl,
    GameSettings? rules,
  }) : rules = rules ?? GameSettings();

  double volume;
  bool muted;
  bool showIntro;
  String serverUrl;
  String feedUrl;
  GameSettings rules;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        volume: (j['volume'] as num?)?.toDouble() ?? 0.9,
        muted: j['muted'] as bool? ?? false,
        showIntro: j['show_intro'] as bool? ?? true,
        serverUrl: j['server_url'] as String? ?? '',
        feedUrl: j['feed_url'] as String? ?? defaultFeedUrl,
        rules: j['rules'] == null
            ? null
            : GameSettings.fromJson((j['rules'] as Map).cast()),
      );
  Map<String, dynamic> toJson() => {
        'volume': volume,
        'muted': muted,
        'show_intro': showIntro,
        'server_url': serverUrl,
        'feed_url': feedUrl,
        'rules': rules.toJson(),
      };
}

class RosterPlayer {
  RosterPlayer(this.id, this.name);
  final String id;
  String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory RosterPlayer.fromJson(Map<String, dynamic> j) =>
      RosterPlayer(j['id'] as String, j['name'] as String);
}

/// Summary of a finished match for the statistics screen.
class MatchRecord {
  MatchRecord(this.id, this.startedAt, this.finishedAt, this.players, this.questions);
  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<PlayerState> players; // ranked
  final int questions;

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
        j['id'] as String,
        DateTime.parse(j['started'] as String),
        DateTime.parse(j['finished'] as String),
        [for (final p in j['players'] as List) PlayerState.fromJson((p as Map).cast())],
        j['questions'] as int? ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'started': startedAt.toUtc().toIso8601String(),
        'finished': finishedAt.toUtc().toIso8601String(),
        'players': players.map((p) => p.toJson()).toList(),
        'questions': questions,
      };
}

/// Single source of truth for the app. Screens listen to it; every change
/// to the match is persisted immediately so the game survives the app being
/// killed.
class AppController extends ChangeNotifier {
  AppController({
    required this.files,
    required this.sound,
    this.loadSeed,
    this.sourceOverride,
    this.scheduler,
  });

  final KeyValueStore files;

  /// Retry scheduler for the question supply (tests use a manual one).
  final Scheduler? scheduler;
  final SoundService sound;

  /// Loads the bundled starter pack (overridable in tests).
  final Future<String> Function()? loadSeed;

  /// Replaces the network sources (tests).
  final List<QuestionSource>? sourceOverride;

  AppSettings settings = AppSettings();
  final List<RosterPlayer> roster = [];
  final List<MatchRecord> history = [];
  GameSession? session;

  /// Full question objects used in the current match (for resume + log).
  final Map<String, Question> usedQuestions = {};
  late QuestionSupply supply;
  bool ready = false;
  final _rnd = Random();

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

  Future<void> init() async {
    final s = await files.read('settings');
    if (s is Map) settings = AppSettings.fromJson(s.cast());
    sound
      ..volume = settings.volume
      ..muted = settings.muted;
    final r = await files.read('roster');
    if (r is List) {
      roster
        ..clear()
        ..addAll(r.map((e) => RosterPlayer.fromJson((e as Map).cast())));
    }
    final h = await files.read('history');
    if (h is List) {
      history
        ..clear()
        ..addAll(h.map((e) => MatchRecord.fromJson((e as Map).cast())));
    }
    _buildSupply();
    await supply.init();
    await _loadSeed();
    final cur = await files.read('current_session');
    if (cur is Map) {
      try {
        session = GameSession.fromJson((cur['session'] as Map).cast());
        for (final e in cur['used_full'] as List? ?? const []) {
          final q = Question.fromJson((e as Map).cast());
          usedQuestions[q.id] = q;
        }
        if (session!.finished) session = null;
      } catch (e) {
        debugPrint('could not restore session: $e');
        session = null;
      }
    }
    ready = true;
    notifyListeners();
  }

  List<QuestionSource> _sources() {
    if (sourceOverride != null) return sourceOverride!;
    return [
      if (settings.serverUrl.trim().isNotEmpty) ServerSource(settings.serverUrl.trim()),
      if (settings.feedUrl.trim().isNotEmpty) FeedSource(settings.feedUrl.trim()),
    ];
  }

  void _buildSupply() {
    supply = QuestionSupply(
      sources: _sources(),
      cache: FileQuestionCache(files),
      history: FileHistoryStore(files),
      scheduler: scheduler,
      onChange: notifyListeners,
    );
  }

  Future<void> _loadSeed() async {
    try {
      final raw = await (loadSeed ?? () => rootBundle.loadString('assets/data/seed_questions.json'))();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      supply.seed([
        for (final e in j['questions'] as List) Question.fromJson((e as Map).cast()),
      ]);
    } catch (e) {
      debugPrint('seed load failed: $e');
    }
  }

  // ---------------------------------------------------------------- settings
  Future<void> saveSettings() async {
    sound
      ..volume = settings.volume
      ..muted = settings.muted;
    await files.write('settings', settings.toJson());
    notifyListeners();
  }

  /// Re-creates the question supply after the source URLs changed.
  Future<void> applySourceSettings() async {
    await saveSettings();
    final wasActive = supply.active;
    final cached = supply.cachedQuestions.toList();
    _buildSupply();
    await supply.init();
    supply.seed(cached);
    await _loadSeed();
    if (wasActive && session != null) {
      await supply.startSession(alreadyUsed: usedQuestions.values.toList());
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ roster
  Future<void> _saveRoster() async {
    await files.write('roster', roster.map((p) => p.toJson()).toList());
    notifyListeners();
  }

  Future<void> addRosterPlayer(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    roster.add(RosterPlayer(newId(), n));
    await _saveRoster();
  }

  Future<void> renameRosterPlayer(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    roster.firstWhere((p) => p.id == id).name = n;
    // Keep the live match in sync.
    final s = session;
    if (s != null && s.players.any((p) => p.id == id)) {
      s.renamePlayer(id, n);
      await persistSession();
    }
    await _saveRoster();
  }

  Future<void> removeRosterPlayer(String id) async {
    roster.removeWhere((p) => p.id == id);
    await _saveRoster();
  }

  // ------------------------------------------------------------------- match
  bool get hasResumableMatch => session != null && !session!.finished;

  Future<void> startNewMatch(List<RosterPlayer> players) async {
    if (session != null) await abandonMatch();
    session = GameSession(
      id: newId(),
      players: [for (final p in players) PlayerState(id: p.id, name: p.name)],
      settings: settings.rules.copy(),
    );
    usedQuestions.clear();
    await supply.startSession();
    sound.play(Sfx.start);
    await persistSession();
  }

  /// Called when the app reopens with an unfinished match.
  Future<void> resumeMatch() async {
    if (session == null) return;
    if (!supply.active) {
      await supply.startSession(alreadyUsed: usedQuestions.values.toList());
    }
    notifyListeners();
  }

  Future<void> persistSession() async {
    final s = session;
    if (s == null) {
      await files.delete('current_session');
    } else {
      await files.write('current_session', {
        'session': s.toJson(),
        'used_full': usedQuestions.values.map((q) => q.toJson()).toList(),
      });
    }
    notifyListeners();
  }

  /// Next question of a section (null while the background fetch runs).
  Question? drawQuestion(Category c) {
    final q = supply.next(c);
    if (q != null) _markUsed(q);
    return q;
  }

  Question? drawSpecific(String id) {
    final q = supply.take(id);
    if (q != null) _markUsed(q);
    return q;
  }

  void _markUsed(Question q) {
    usedQuestions[q.id] = q;
    session?.markUsed(q);
  }

  /// Saves the in-progress round so it can be resumed.
  Future<void> saveRound(Round? round, Question? q) async {
    final s = session;
    if (s == null) return;
    s.activeRound = (round == null || round.done || q == null)
        ? null
        : {'round': round.toJson(), 'question': q.toJson()};
    await persistSession();
  }

  Future<void> completeRound(Round round, Question q) async {
    final s = session;
    if (s == null) return;
    s.roundsPlayed++;
    await saveRound(null, null);
  }

  (Round, Question)? get pendingRound {
    final a = session?.activeRound;
    if (a == null) return null;
    try {
      return (
        Round.fromJson((a['round'] as Map).cast()),
        Question.fromJson((a['question'] as Map).cast()),
      );
    } catch (_) {
      return null;
    }
  }

  /// Ends the match: records it in the history and frees the session.
  Future<MatchRecord?> finishMatch() async {
    final s = session;
    if (s == null) return null;
    s.finish();
    final rec = MatchRecord(s.id, s.createdAt, s.finishedAt!, s.ranking, s.used.length);
    history.insert(0, rec);
    await files.write('history', history.map((m) => m.toJson()).toList());
    await supply.endSession();
    session = null;
    usedQuestions.clear();
    await persistSession();
    return rec;
  }

  Future<void> abandonMatch() async {
    if (session == null) return;
    await supply.endSession();
    session = null;
    usedQuestions.clear();
    await persistSession();
  }

  Future<void> clearHistory() async {
    history.clear();
    await files.write('history', const []);
    notifyListeners();
  }
}
