import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../../services/sound.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/effects.dart';
import '../../widgets/round_timer.dart';
import 'round_common.dart';

class WdykScreen extends RoundScreen {
  const WdykScreen({super.key, super.resume});
  @override
  Category get category => Category.whatDoYouKnow;
  @override
  State<WdykScreen> createState() => _WdykScreenState();
}

class _WdykScreenState extends RoundScreenState<WdykScreen, WdykRound>
    with NextQuestion<WdykScreen, WdykRound> {
  RoundTimerController? _timer;

  @override
  WdykRound createRound(Question q) =>
      WdykRound.start(session, q.id, session.activePlayers.first.id);

  RoundTimerController get timer => _timer ??=
      RoundTimerController(seconds: session.settings.wdykSeconds, sound: app.sound);

  @override
  void onNewQuestion() => _timer?.reset(seconds: session.settings.wdykSeconds);

  @override
  void dispose() {
    _timer?.dispose();
    super.dispose();
  }

  Future<void> _after(TurnOutcome o) async {
    timer.reset();
    setState(() {});
    await persist();
    await app.persistSession();
    if (!mounted) return;
    switch (o.result) {
      case TurnResult.correct:
        app.sound.play(Sfx.correct);
        flashVerdict(context, correct: true, text: '+${session.settings.wdykPoints}');
      case TurnResult.passed:
        app.sound.play(Sfx.pass);
      case TurnResult.wrong || TurnResult.exhausted:
        app.sound.play(o.strike != null ? Sfx.strike : Sfx.pass);
        if (o.strike != null) flashVerdict(context, correct: false, text: 'STRIKE ${o.strike!.strikes}');
      case TurnResult.eliminated:
        app.sound.play(Sfx.eliminated);
        await showElimination(context, session.player(o.playerId).name);
    }
  }

  @override
  Widget buildRound(BuildContext context, Question q, WdykRound r) {
    final cur = r.current == null ? null : session.player(r.current!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: [
        QuestionCard(question: q),
        const SizedBox(height: 14),
        if (!r.done) ...[
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: C.cyan.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: C.cyan.withValues(alpha: .6), width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('الدور على', style: TextStyle(color: C.muted)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(cur?.name ?? '',
                        key: ValueKey(cur?.id),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 6),
                  if (cur != null) StrikeMarks(strikes: cur.strikes, limit: session.settings.strikeLimit, size: 20),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            TimerRing(controller: timer, size: 100, color: C.cyan),
          ]),
          const SizedBox(height: 12),
          const Text('تحديد اللاعب الذي يبدأ / صاحب الدور:', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          PlayerChips(
            session: session,
            selected: r.current,
            onSelect: (id) {
              setState(() => r.setCurrent(id));
              persist();
            },
          ),
          const SizedBox(height: 10),
          _OrderStrip(session: session, r: r),
          const SizedBox(height: 14),
          VerdictButtons(
            onCorrect: () => _after(r.correct(session)),
            onWrong: () => _after(r.wrong(session)),
            extra: GlowButton(
              key: const Key('pass'),
              label: 'PASS',
              icon: Icons.fast_forward_rounded,
              color: C.cyan,
              filled: false,
              onPressed: () => _after(r.pass(session)),
            ),
          ),
          const SizedBox(height: 12),
          SecretAnswer(question: q),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(r.close);
              persist();
              app.sound.play(Sfx.reveal);
            },
            child: const Text('كشف الإجابة وإنهاء السؤال دون نقاط', style: TextStyle(color: C.muted)),
          ),
        ] else
          RoundDone(
            question: q,
            title: r.winnerId != null ? 'أجاب ${session.player(r.winnerId!).name} بشكل صحيح' : 'لم يجب أحد',
            color: r.winnerId != null ? C.pitch : C.orange,
            onNext: nextQuestion,
            onBack: closeRound,
          ),
      ],
    );
  }
}

class _OrderStrip extends StatelessWidget {
  const _OrderStrip({required this.session, required this.r});
  final GameSession session;
  final WdykRound r;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final id in r.order)
            Builder(builder: (_) {
              final p = session.player(id);
              final isCur = id == r.current;
              final passed = r.passedBy.contains(id);
              final failed = r.tried.contains(id) && !passed;
              final col = p.eliminated
                  ? C.red
                  : isCur
                      ? C.cyan
                      : failed
                          ? C.red
                          : passed
                              ? C.muted
                              : C.text;
              return Container(
                margin: const EdgeInsetsDirectional.only(end: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: col.withValues(alpha: isCur ? .18 : .06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: col.withValues(alpha: .5)),
                ),
                child: Text(
                  '${p.name}${passed ? ' · PASS' : ''}${failed ? ' · خطأ' : ''}',
                  style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              );
            }),
        ]),
      );
}
