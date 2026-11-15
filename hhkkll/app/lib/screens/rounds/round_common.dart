import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../../app.dart';
import '../../services/controller.dart';
import '../../services/sound.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/referee_panel.dart';

abstract class RoundScreen extends StatefulWidget {
  const RoundScreen({super.key, this.resume});

  /// Round + question restored after the app was closed mid-round.
  final (Round, Question)? resume;
  Category get category;
}

/// Shared behaviour of the four section screens: drawing a fresh question
/// (waiting for the background fetch if needed), changing / choosing the
/// question, persisting the round after every action, the referee panel and
/// the source info — all without leaving the question screen.
abstract class RoundScreenState<W extends RoundScreen, R extends Round> extends State<W> {
  Question? question;
  R? round;

  /// Set while leaving the screen so no new question is drawn.
  bool _closing = false;

  AppController get app => AppScope.read(context);
  GameSession get session => app.session!;
  Category get category => widget.category;

  /// Builds a fresh round for [q].
  R createRound(Question q);

  /// The round-specific UI.
  Widget buildRound(BuildContext context, Question q, R r);

  /// Called when a new question is loaded (reset local UI state).
  void onNewQuestion() {}

  @override
  void initState() {
    super.initState();
    final res = widget.resume;
    if (res != null && res.$1 is R) {
      question = res.$2;
      round = res.$1 as R;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _draw());
    }
  }

  void _draw({String? specificId}) {
    if (!mounted || _closing) return;
    final q = specificId != null ? app.drawSpecific(specificId) : app.drawQuestion(category);
    if (q == null) {
      setState(() {}); // waiting view; rebuilt when the supply notifies
      return;
    }
    setState(() {
      question = q;
      round = createRound(q);
    });
    onNewQuestion();
    app.sound.play(Sfx.question);
    persist();
  }

  Future<void> persist() => app.saveRound(round, question);

  /// Referee: replace the current question (it stays marked as used).
  Future<void> changeQuestion() async {
    final ok = await _confirm('تغيير السؤال؟', 'سيُسجَّل السؤال الحالي كمستخدم ولن يتكرر.');
    if (ok != true) return;
    setState(() {
      question = null;
      round = null;
    });
    _draw();
  }

  Future<void> pickQuestion() async {
    final queue = app.supply.peekQueue(category);
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .75,
        child: queue.isEmpty
            ? const Center(child: Text('لا توجد أسئلة جاهزة الآن — الجلب جارٍ', style: TextStyle(color: C.muted)))
            : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: queue.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final q = queue[i];
                  return ListTile(
                    title: Text(q.category == Category.whoAmI ? 'من أنا؟ (${q.clues.length} تلميحات)' : q.text,
                        style: const TextStyle(fontSize: 14, height: 1.6)),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: VerificationBadge(q)),
                    onTap: () => Navigator.pop(ctx, q.id),
                  );
                },
              ),
      ),
    );
    if (id == null || !mounted) return;
    setState(() {
      question = null;
      round = null;
    });
    _draw(specificId: id);
  }

  /// Ends the round and returns to the hub.
  Future<void> closeRound() async {
    _closing = true;
    final q = question, r = round;
    if (q != null && r != null) {
      if (r.done) {
        await app.completeRound(r, q);
      } else {
        await persist();
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      );

  /// Abandons an unfinished round (no points) and goes back.
  Future<void> abandonRound() async {
    final r = round;
    if (r != null && !r.done) {
      final ok = await _confirm('إنهاء الجولة؟', 'لم تُحسم الجولة بعد. ستُغلق دون احتساب نقاط.');
      if (ok != true) return;
      _closing = true;
      round = null;
      question = null;
      await app.saveRound(null, null);
    }
    if (mounted) await closeRound();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context); // rebuild on supply / session changes
    if (!_closing && question == null && c.supply.queued(category) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && question == null) _draw();
      });
    }
    final col = C.of(category);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) abandonRound();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('round-close'),
            tooltip: 'العودة للوحة المنافسة',
            icon: const Icon(Icons.close_rounded),
            onPressed: abandonRound,
          ),
          title: SectionTag(category, compact: MediaQuery.sizeOf(context).width < 600),
          actions: [
            IconButton(
              key: const Key('change-question'),
              tooltip: 'تغيير السؤال',
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: question == null ? null : changeQuestion,
            ),
            IconButton(
              key: const Key('pick-question'),
              tooltip: 'اختيار السؤال',
              icon: const Icon(Icons.format_list_numbered_rtl_rounded),
              onPressed: pickQuestion,
            ),
            IconButton(
              key: const Key('referee'),
              tooltip: 'لوحة الحكم',
              icon: Icon(Icons.admin_panel_settings_rounded, color: col),
              onPressed: () => showRefereePanel(context, current: question),
            ),
          ],
        ),
        body: StageBackground(
          accent: col,
          child: SafeArea(
            top: false,
            child: question == null || round == null
                ? _Waiting(category: category)
                : buildRound(context, question!, round!),
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.category});
  final Category category;
  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).supply.status;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: C.of(category)),
          const SizedBox(height: 20),
          Text(
            st.online ? 'جاري توليد أسئلة جديدة لهذا القسم…' : 'لا يوجد اتصال ونفدت أسئلة هذا القسم من المخزون.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.7),
          ),
          const SizedBox(height: 8),
          Text(
            st.online
                ? 'سيظهر السؤال تلقائياً فور وصوله.'
                : 'سيُعاد الاتصال تلقائياً عند عودة الإنترنت. يمكنك اللعب في قسم آخر الآن.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, height: 1.7),
          ),
          if (st.lastError != null) ...[
            const SizedBox(height: 8),
            Text(st.lastError!, textAlign: TextAlign.center, textDirection: TextDirection.ltr,
                style: const TextStyle(color: C.muted, fontSize: 11)),
          ],
        ]),
      ),
    );
  }
}

/// Big question card shown to the players.
class QuestionCard extends StatelessWidget {
  const QuestionCard({super.key, required this.question, this.fontSize = 22});
  final Question question;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final col = C.of(question.category);
    return TweenAnimationBuilder<double>(
      key: ValueKey(question.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: C.surface.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: col.withValues(alpha: .5)),
          boxShadow: [BoxShadow(color: col.withValues(alpha: .15), blurRadius: 30)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          VerificationBadge(question),
          const SizedBox(height: 12),
          Text(question.text,
              key: const Key('question-text'),
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, height: 1.65)),
          if (question.factAsOf != null) ...[
            const SizedBox(height: 6),
            Text('المعلومة حتى ${question.factAsOf}', style: const TextStyle(color: C.muted, fontSize: 11)),
          ],
        ]),
      ),
    );
  }
}

/// Player picker chips (who is answering).
class PlayerChips extends StatelessWidget {
  const PlayerChips({
    super.key,
    required this.session,
    required this.selected,
    required this.onSelect,
    this.enabled,
  });
  final GameSession session;
  final String? selected;
  final void Function(String id) onSelect;
  final bool Function(PlayerState p)? enabled;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, p) in session.players.indexed)
            if (!p.eliminated)
              ChoiceChip(
                key: Key('chip-${p.name}'),
                label: Text(p.name),
                selected: p.id == selected,
                selectedColor: C.player(i).withValues(alpha: .3),
                side: BorderSide(color: C.player(i).withValues(alpha: .7)),
                onSelected: (enabled?.call(p) ?? true) ? (_) => onSelect(p.id) : null,
              ),
        ],
      );
}

/// Correct / wrong buttons for the referee.
class VerdictButtons extends StatelessWidget {
  const VerdictButtons({super.key, required this.onCorrect, required this.onWrong, this.extra});
  final VoidCallback? onCorrect;
  final VoidCallback? onWrong;
  final Widget? extra;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: GlowButton(
            key: const Key('verdict-correct'),
            label: 'صح',
            icon: Icons.check_rounded,
            color: C.pitch,
            onPressed: onCorrect,
          ),
        ),
        if (extra != null) ...[const SizedBox(width: 10), Expanded(child: extra!)],
        const SizedBox(width: 10),
        Expanded(
          child: GlowButton(
            key: const Key('verdict-wrong'),
            label: 'خطأ',
            icon: Icons.close_rounded,
            color: C.red,
            onPressed: onWrong,
          ),
        ),
      ]);
}

/// Shown when a round is decided: reveal + next question / back to board.
class RoundDone extends StatelessWidget {
  const RoundDone({super.key, required this.question, required this.title, required this.color, required this.onNext, required this.onBack});
  final Question question;
  final String title;
  final Color color;
  final VoidCallback onNext;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .5)),
        ),
        child: Column(children: [
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('الإجابة: ${question.answer}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: GlowButton(key: const Key('next-question'), label: 'السؤال التالي', icon: Icons.skip_next_rounded, color: C.of(question.category), onPressed: onNext)),
            const SizedBox(width: 10),
            Expanded(child: GlowButton(key: const Key('back-to-board'), label: 'لوحة المنافسة', icon: Icons.leaderboard_rounded, filled: false, color: C.text, onPressed: onBack)),
          ]),
        ]),
      );
}

/// Next question in the same section after the round was decided.
mixin NextQuestion<W extends RoundScreen, R extends Round> on RoundScreenState<W, R> {
  Future<void> nextQuestion() async {
    final q = question, r = round;
    if (q != null && r != null && r.done) await app.completeRound(r, q);
    setState(() {
      question = null;
      round = null;
    });
    _draw();
  }
}
