import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../../services/sound.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/effects.dart';
import 'round_common.dart';

class WhoAmIScreen extends RoundScreen {
  const WhoAmIScreen({super.key, super.resume});
  @override
  Category get category => Category.whoAmI;
  @override
  State<WhoAmIScreen> createState() => _WhoAmIScreenState();
}

class _WhoAmIScreenState extends RoundScreenState<WhoAmIScreen, WhoAmIRound>
    with NextQuestion<WhoAmIScreen, WhoAmIRound> {
  String? _answering;
  bool _peekNext = false;

  @override
  WhoAmIRound createRound(Question q) => WhoAmIRound(questionId: q.id, clueCount: q.clues.length);

  @override
  void onNewQuestion() {
    _answering = null;
    _peekNext = false;
  }

  void _reveal() {
    setState(() {
      round!.revealNext();
      _answering = null;
    });
    app.sound.play(Sfx.reveal);
    persist();
  }

  Future<void> _judge(bool correct) async {
    final r = round!, p = _answering;
    if (p == null) return;
    final o = correct ? r.correct(session, p) : r.wrong(session, p);
    setState(() => _answering = null);
    await persist();
    await app.persistSession();
    if (!mounted) return;
    if (correct) {
      app.sound.play(Sfx.correct);
      flashVerdict(context, correct: true, text: '+${r.pointsAwarded}');
    } else if (o.result == TurnResult.eliminated) {
      app.sound.play(Sfx.eliminated);
      await showElimination(context, session.player(p).name);
    } else {
      app.sound.play(o.strike != null ? Sfx.strike : Sfx.wrong);
      flashVerdict(context, correct: false);
    }
  }

  @override
  Widget buildRound(BuildContext context, Question q, WhoAmIRound r) {
    final pts = r.currentPoints(session);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: [
        Row(children: [
          const Text('من أنا؟', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (!r.done)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: C.violet.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.violet),
              ),
              child: Text(r.revealed == 0 ? 'اكشف التلميح الأول' : 'قيمة الإجابة الآن: $pts',
                  key: const Key('whoami-points'),
                  style: const TextStyle(color: C.violet, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 4),
        VerificationBadge(q),
        const SizedBox(height: 14),
        for (var i = 0; i < q.clues.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ClueCard(
              index: i,
              text: q.clues[i],
              revealed: i < r.revealed || r.done,
              points: session.settings.whoAmIPointsFor(i + 1),
              peek: _peekNext && i == r.revealed,
            ),
          ),
        if (!r.done) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: GlowButton(
                key: const Key('reveal-clue'),
                label: r.canReveal ? 'كشف التلميح ${r.revealed + 1}' : 'كُشفت كل التلميحات',
                icon: Icons.lightbulb_rounded,
                color: C.violet,
                onPressed: r.canReveal ? _reveal : null,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPressStart: (_) => setState(() => _peekNext = true),
              onLongPressEnd: (_) => setState(() => _peekNext = false),
              child: const Tooltip(
                message: 'اضغط مطولاً لرؤية التلميح التالي (للحكم)',
                child: CircleAvatar(backgroundColor: C.surface2, child: Icon(Icons.visibility_rounded, color: C.muted)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (r.revealed > 0) ...[
            const Text('من يحاول الإجابة؟', style: TextStyle(color: C.muted)),
            const SizedBox(height: 6),
            PlayerChips(
              session: session,
              selected: _answering,
              enabled: (p) => r.canAttempt(session, p.id),
              onSelect: (id) => setState(() => _answering = id),
            ),
            const SizedBox(height: 12),
            VerdictButtons(
              onCorrect: _answering == null ? null : () => _judge(true),
              onWrong: _answering == null ? null : () => _judge(false),
            ),
          ],
          const SizedBox(height: 12),
          SecretAnswer(question: q),
          TextButton(
            onPressed: () {
              setState(r.close);
              persist();
              app.sound.play(Sfx.reveal);
            },
            child: const Text('كشف الشخصية وإنهاء اللغز', style: TextStyle(color: C.muted)),
          ),
        ] else
          RoundDone(
            question: q,
            title: r.winnerId != null
                ? '${session.player(r.winnerId!).name} عرفه من التلميح ${r.revealed}!  +${r.pointsAwarded}'
                : 'لم يعرفه أحد',
            color: r.winnerId != null ? C.pitch : C.orange,
            onNext: nextQuestion,
            onBack: closeRound,
          ),
      ],
    );
  }
}

class _ClueCard extends StatelessWidget {
  const _ClueCard({required this.index, required this.text, required this.revealed, required this.points, required this.peek});
  final int index;
  final String text;
  final bool revealed, peek;
  final int points;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SizeTransition(sizeFactor: a, child: c),
        ),
        child: Container(
          key: ValueKey('$index-$revealed-$peek'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: revealed ? C.violet.withValues(alpha: .12) : C.surface.withValues(alpha: .85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: revealed ? C.violet.withValues(alpha: .7) : C.line),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: revealed ? C.violet : C.surface2,
              child: Text('${index + 1}', style: TextStyle(color: revealed ? Colors.white : C.muted, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: revealed || peek
                  ? Text(text,
                      key: Key('clue-$index'),
                      style: TextStyle(fontSize: 17, height: 1.6, fontWeight: FontWeight.w700, color: peek && !revealed ? C.muted : C.text))
                  : const Text('تلميح مخفي', style: TextStyle(color: C.muted)),
            ),
            Text('$points', textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'Display', color: C.muted)),
          ]),
        ),
      );
}
