import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../../services/sound.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/effects.dart';
import '../../widgets/round_timer.dart';
import 'round_common.dart';

/// Monotonic clock for reaction times (immune to wall-clock changes).
final Stopwatch _mono = Stopwatch()..start();
int monoMicros() => _mono.elapsedMicroseconds;

class BuzzerScreen extends RoundScreen {
  const BuzzerScreen({super.key, super.resume});
  @override
  Category get category => Category.buzzer;
  @override
  State<BuzzerScreen> createState() => _BuzzerScreenState();
}

class _BuzzerScreenState extends RoundScreenState<BuzzerScreen, BuzzerRound>
    with NextQuestion<BuzzerScreen, BuzzerRound> {
  int _count = 0;
  Timer? _countdown;
  RoundTimerController? _answerTimer;
  int _flashKey = 0;

  @override
  BuzzerRound createRound(Question q) => BuzzerRound(questionId: q.id);

  RoundTimerController get answerTimer => _answerTimer ??= RoundTimerController(
    seconds: session.settings.buzzerAnswerSeconds,
    sound: app.sound,
  );

  @override
  void onNewQuestion() {
    _countdown?.cancel();
    _count = 0;
    _answerTimer?.reset(seconds: session.settings.buzzerAnswerSeconds);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _answerTimer?.dispose();
    super.dispose();
  }

  void _start({bool reopen = false}) {
    final r = round!;
    if (!reopen) r.startCountdown();
    _count = session.settings.buzzerCountdown;
    setState(() {});
    if (_count <= 0) return _open(reopen);
    app.sound.play(Sfx.tick);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      _count--;
      if (_count <= 0) {
        t.cancel();
        _open(reopen);
      } else {
        app.sound.play(_count == 1 ? Sfx.tickLast : Sfx.tick);
      }
      if (mounted) setState(() {});
    });
  }

  void _open(bool reopen) {
    final r = round!;
    reopen ? r.reopen(monoMicros()) : r.open(monoMicros());
    app.sound.play(Sfx.go);
    answerTimer.reset(seconds: session.settings.buzzerAnswerSeconds);
    setState(() {});
  }

  void _press(String playerId) {
    final r = round!;
    final res = r.press(session, playerId, monoMicros());
    if (!res.accepted) return;
    // Lock happened synchronously inside press(); everything below is UI.
    HapticFeedback.heavyImpact();
    app.sound.play(Sfx.buzzer);
    _flashKey++;
    answerTimer
      ..reset(seconds: session.settings.buzzerAnswerSeconds)
      ..start();
    setState(() {});
    persist();
  }

  Future<void> _judge(bool correct) async {
    final r = round!;
    answerTimer.pause();
    final o = correct ? r.correct(session) : r.wrong(session);
    setState(() {});
    await persist();
    await app.persistSession();
    if (!mounted) return;
    if (correct) {
      app.sound.play(Sfx.correct);
      flashVerdict(
        context,
        correct: true,
        text: '+${session.settings.buzzerPoints}',
      );
    } else if (o.result == TurnResult.eliminated) {
      app.sound.play(Sfx.eliminated);
      await showElimination(context, session.player(o.playerId).name);
    } else {
      app.sound.play(Sfx.strike);
      flashVerdict(
        context,
        correct: false,
        text: 'STRIKE ${o.strike?.strikes ?? ''}',
      );
    }
  }

  @override
  Widget buildRound(BuildContext context, Question q, BuzzerRound r) {
    final phase = r.phase;
    final showQuestion =
        phase != BuzzerPhase.ready && phase != BuzzerPhase.countdown;
    final locked = r.lockedBy == null ? null : session.player(r.lockedBy!);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            children: [
              if (showQuestion)
                QuestionCard(question: q, fontSize: 24)
              else
                _HiddenQuestion(
                  countdown: phase == BuzzerPhase.countdown ? _count : null,
                ),
              const SizedBox(height: 12),
              if (phase == BuzzerPhase.ready) ...[
                SecretAnswer(question: q),
                const SizedBox(height: 14),
                GlowButton(
                  key: const Key('buzzer-start'),
                  label: 'START',
                  icon: Icons.play_arrow_rounded,
                  color: C.red,
                  height: 66,
                  onPressed: _start,
                ),
              ],
              if (phase == BuzzerPhase.open)
                const Center(
                  child: Text(
                    'الجرس مفتوح — أول من يضغط يجيب!',
                    style: TextStyle(
                      color: C.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              if (phase == BuzzerPhase.locked && locked != null) ...[
              _LockedBanner(
                key: ValueKey(_flashKey),
                name: locked.name,
                color: _colorOf(locked.id),
                ms: r.presses.lastWhere((p) => p.accepted).reactionMs,
                timer: TimerRing(controller: answerTimer, size: 74, color: C.red, showControls: false),
              ),
              const SizedBox(height: 10),
              VerdictButtons(onCorrect: () => _judge(true), onWrong: () => _judge(false)),
              const SizedBox(height: 10),
              SecretAnswer(question: q),
            ],
            if (phase == BuzzerPhase.judged) ...[
                Text(
                  'أخطأ: ${r.lockedOut.map((id) => session.player(id).name).join('، ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: C.red),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GlowButton(
                        key: const Key('buzzer-reopen'),
                        label: 'فتح الجرس للبقية',
                        icon: Icons.lock_open_rounded,
                        color: C.red,
                        onPressed: () => _start(reopen: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlowButton(
                        label: 'إنهاء السؤال',
                        icon: Icons.stop_rounded,
                        filled: false,
                        color: C.muted,
                        onPressed: () {
                          setState(r.close);
                          persist();
                        },
                      ),
                    ),
                  ],
                ),
              ],
              if (phase == BuzzerPhase.done)
                RoundDone(
                  question: q,
                  title: r.winnerId != null
                      ? 'أصاب ${session.player(r.winnerId!).name}!'
                      : 'لم يُجب أحد بشكل صحيح',
                  color: r.winnerId != null ? C.pitch : C.orange,
                  onNext: nextQuestion,
                  onBack: closeRound,
                ),
              if (r.presses.length > 1 && phase != BuzzerPhase.ready) ...[
                const SizedBox(height: 10),
                _PressLog(session: session, presses: r.presses),
              ],
            ],
          ),
        ),
        if (phase != BuzzerPhase.done)
          _BuzzerPad(
            session: session,
            round: r,
            colorOf: _colorOf,
            onPress: _press,
          ),
      ],
    );
  }

  Color _colorOf(String id) =>
      C.player(session.players.indexWhere((p) => p.id == id));
}

class _HiddenQuestion extends StatelessWidget {
  const _HiddenQuestion({this.countdown});
  final int? countdown;
  @override
  Widget build(BuildContext context) => Container(
    height: 150,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: C.surface.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: C.red.withValues(alpha: .4)),
    ),
    child: countdown == null
        ? const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_rounded, color: C.muted, size: 34),
              SizedBox(height: 6),
              Text(
                'السؤال مخفي حتى يضغط الحكم START',
                style: TextStyle(color: C.muted),
              ),
            ],
          )
        : TweenAnimationBuilder<double>(
            key: ValueKey(countdown),
            tween: Tween(begin: 2.2, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (_, s, _) => Transform.scale(
              scale: s,
              child: Text(
                '$countdown',
                key: const Key('countdown'),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'Display',
                  fontSize: 90,
                  fontWeight: FontWeight.w700,
                  color: C.red,
                  shadows: [Shadow(color: C.red, blurRadius: 30)],
                ),
              ),
            ),
          ),
  );
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({
    super.key,
    required this.name,
    required this.color,
    required this.ms,
    required this.timer,
  });
  final String name;
  final Color color;
  final int ms;
  final Widget timer;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 700),
    builder: (_, t, _) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.lerp(
          Colors.white,
          color.withValues(alpha: .2),
          Curves.easeOut.transform(t),
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .5 * (1 - t) + .2),
            blurRadius: 40,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: C.text,
                  size: 26,
                ),
                Text(
                  name,
                  key: const Key('buzz-winner'),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                ),
                Text('ضغط أولاً · $ms ms', style: const TextStyle(color: C.muted)),
              ],
            ),
          ),
          timer,
        ],
      ),
    ),
  );
}

class _PressLog extends StatelessWidget {
  const _PressLog({required this.session, required this.presses});
  final GameSession session;
  final List<BuzzResult> presses;
  @override
  Widget build(BuildContext context) => Text(
    presses
        .map(
          (p) =>
              '${session.player(p.playerId).name} ${p.reactionMs}ms${p.accepted ? ' (الأول)' : ''}',
        )
        .join('  ·  '),
    textAlign: TextAlign.center,
    style: const TextStyle(color: C.muted, fontSize: 11),
  );
}

/// One big buzzer per active player. Uses raw pointer-down events (fires on
/// touch, not on release) and supports several fingers at once.
class _BuzzerPad extends StatelessWidget {
  const _BuzzerPad({
    required this.session,
    required this.round,
    required this.colorOf,
    required this.onPress,
  });
  final GameSession session;
  final BuzzerRound round;
  final Color Function(String) colorOf;
  final void Function(String) onPress;

  @override
  Widget build(BuildContext context) {
    final players = session.activePlayers;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 760;
    final n = players.length;
    final cols = n <= 2
        ? n
        : (wide ? (n <= 4 ? n : (n <= 6 ? 3 : 4)) : (n <= 4 ? 2 : 3));
    final rows = (n / cols).ceil();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: const BoxDecoration(
        color: C.bg2,
        border: Border(top: BorderSide(color: C.line)),
      ),
      height: (size.height * (wide ? .38 : .32)).clamp(170.0, 380.0),
      // Every buzzer must be visible at once: tile size is computed from the
      // space available, never scrolled.
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 8.0;
          final tileW = (box.maxWidth - gap * (cols - 1)) / cols;
          final tileH = (box.maxHeight - gap * (rows - 1)) / rows;
          return GridView.count(
            crossAxisCount: cols,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: tileW / tileH,
            children: [
              for (final p in players)
                _Buzzer(
                  key: Key('buzz-${p.name}'),
                  name: p.name,
                  color: colorOf(p.id),
                  armed:
                      round.phase == BuzzerPhase.open &&
                      !round.lockedOut.contains(p.id),
                  winner: round.lockedBy == p.id,
                  out: round.lockedOut.contains(p.id),
                  onDown: () => onPress(p.id),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Buzzer extends StatelessWidget {
  const _Buzzer({
    super.key,
    required this.name,
    required this.color,
    required this.armed,
    required this.winner,
    required this.out,
    required this.onDown,
  });
  final String name;
  final Color color;
  final bool armed, winner, out;
  final VoidCallback onDown;
  @override
  Widget build(BuildContext context) {
    final lit = armed || winner;
    return Listener(
      onPointerDown: (_) => onDown(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: RadialGradient(
            colors: lit
                ? [
                    Color.lerp(color, Colors.white, winner ? .45 : .15)!,
                    color.withValues(alpha: .7),
                  ]
                : [C.surface2, C.surface],
          ),
          border: Border.all(
            color: out ? C.red : color.withValues(alpha: lit ? 1 : .35),
            width: winner ? 4 : 2,
          ),
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: winner ? .9 : .45),
                    blurRadius: winner ? 40 : 18,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              out ? Icons.block_rounded : Icons.radio_button_checked_rounded,
              color: lit ? Colors.black.withValues(alpha: .75) : C.muted,
              size: 26,
            ),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: lit ? Colors.black : C.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
