import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../../services/sound.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/effects.dart';
import '../../widgets/round_timer.dart';
import 'round_common.dart';

class AuctionScreen extends RoundScreen {
  const AuctionScreen({super.key, super.resume});
  @override
  Category get category => Category.auction;
  @override
  State<AuctionScreen> createState() => _AuctionScreenState();
}

class _AuctionScreenState extends RoundScreenState<AuctionScreen, AuctionRound>
    with NextQuestion<AuctionScreen, AuctionRound> {
  RoundTimerController? _timer;
  bool _showList = false;
  String? _error;

  @override
  AuctionRound createRound(Question q) => AuctionRound(
        questionId: q.id,
        participants: session.activePlayers.map((p) => p.id).toList(),
        maxBid: q.itemsExhaustive ? q.items.length : null,
      );

  @override
  void onNewQuestion() {
    _timer?.dispose();
    _timer = null;
    _showList = false;
    _error = null;
  }

  RoundTimerController _ensureTimer() => _timer ??= RoundTimerController(
        seconds: session.settings.auctionSeconds,
        sound: app.sound,
        onFinished: () {
          if (round?.phase == AuctionPhase.answering) _resolve();
        },
      );

  @override
  void dispose() {
    _timer?.dispose();
    super.dispose();
  }

  void _act(VoidCallback f) {
    try {
      f();
      _error = null;
    } on RoundError catch (e) {
      _error = e.message;
    }
    setState(() {});
    persist();
  }

  Future<void> _customBid(String playerId) async {
    final r = round!;
    final ctl = TextEditingController(text: '${r.highestBid + 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مزايدة ${session.player(playerId).name}'),
        content: TextField(
          key: const Key('bid-field'),
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'العدد'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            key: const Key('bid-ok'),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())),
            child: const Text('مزايدة'),
          ),
        ],
      ),
    );
    if (v != null) {
      _act(() => r.bid(playerId, v));
      if (_error == null) app.sound.play(Sfx.bid);
    }
  }

  void _startAnswering() {
    _act(() => round!.startAnswering());
    if (round!.phase == AuctionPhase.answering) {
      app.sound.play(Sfx.auctionWin);
      _ensureTimer()
        ..reset(seconds: session.settings.auctionSeconds)
        ..start();
    }
  }

  Future<void> _resolve() async {
    final r = round!;
    if (r.phase != AuctionPhase.answering) return;
    _timer?.pause();
    final o = r.resolve(session);
    setState(() {});
    await persist();
    await app.persistSession();
    if (!mounted) return;
    app.sound.play(o.success ? Sfx.correct : Sfx.wrong);
    flashVerdict(context, correct: o.success, text: '${o.achieved} / ${o.target}');
    if (o.strike?.eliminatedNow == true) {
      app.sound.play(Sfx.eliminated);
      await showElimination(context, session.player(o.winnerId).name);
    }
  }

  @override
  Widget buildRound(BuildContext context, Question q, AuctionRound r) {
    final leader = r.highestBidder == null ? null : session.player(r.highestBidder!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: [
        QuestionCard(question: q),
        const SizedBox(height: 14),
        _HighBid(amount: r.highestBid, holder: leader?.name, max: r.maxBid, decided: r.decided),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, key: const Key('auction-error'), textAlign: TextAlign.center, style: const TextStyle(color: C.red)),
        ],
        const SizedBox(height: 14),
        if (r.phase == AuctionPhase.bidding) ..._bidding(r),
        if (r.phase == AuctionPhase.answering) ..._answering(q, r),
        if (r.phase == AuctionPhase.done && r.outcome != null)
          RoundDone(
            question: q,
            title: r.outcome!.success
                ? '${session.player(r.outcome!.winnerId).name} نجح في المزاد! (${r.outcome!.achieved}/${r.outcome!.target})  +${r.outcome!.points}'
                : '${session.player(r.outcome!.winnerId).name} لم يبلغ الهدف (${r.outcome!.achieved}/${r.outcome!.target})  ${r.outcome!.points}',
            color: r.outcome!.success ? C.pitch : C.red,
            onNext: nextQuestion,
            onBack: closeRound,
          ),
        if (r.phase != AuctionPhase.bidding) ...[
          const SizedBox(height: 14),
          _ItemsList(q: q, r: r, open: _showList || r.done, onToggle: () => setState(() => _showList = !_showList), onTap: (i) {
            _act(() => r.toggleItem(i));
            app.sound.play(r.namedItems.contains(i) ? Sfx.correct : Sfx.pass);
          }),
        ],
      ],
    );
  }

  List<Widget> _bidding(AuctionRound r) => [
        for (final (i, id) in r.participants.indexed)
          if (!session.player(id).eliminated)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BidderRow(
                name: session.player(id).name,
                color: C.player(session.players.indexWhere((p) => p.id == id)),
                withdrawn: r.withdrawn.contains(id),
                leading: r.highestBidder == id,
                onPlusOne: () {
                  _act(() => r.bid(id, r.highestBid + 1));
                  if (_error == null) app.sound.play(Sfx.bid);
                },
                onCustom: () => _customBid(id),
                onWithdraw: () {
                  _act(() => r.withdrawn.contains(id) ? r.rejoin(id) : r.withdraw(id));
                  app.sound.play(Sfx.pass);
                },
                index: i,
              ),
            ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: GlowButton(
              key: const Key('undo-bid'),
              label: 'تراجع عن آخر مزايدة',
              icon: Icons.undo_rounded,
              filled: false,
              color: C.muted,
              dense: true,
              onPressed: r.bids.isEmpty ? null : () => _act(r.undoBid),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlowButton(
              key: const Key('close-auction'),
              label: r.decided ? 'بدء الإجابة' : 'إغلاق المزاد',
              icon: Icons.gavel_rounded,
              dense: true,
              onPressed: r.highestBidder == null ? null : _startAnswering,
            ),
          ),
        ]),
      ];

  List<Widget> _answering(Question q, AuctionRound r) {
    final t = _ensureTimer();
    return [
      Row(children: [
        Expanded(
          child: Column(children: [
            Text('${r.correctCount} / ${r.highestBid}',
                key: const Key('auction-progress'),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontFamily: 'Display',
                    fontSize: 54,
                    fontWeight: FontWeight.w700,
                    color: r.reachedTarget ? C.pitch : C.gold)),
            Text('أسماء صحيحة   ·   أخطاء: ${r.wrongNames}', style: const TextStyle(color: C.muted)),
          ]),
        ),
        TimerRing(controller: t, size: 110),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: GlowButton(
            key: const Key('extra-correct'),
            label: '+ اسم صحيح',
            icon: Icons.add_task_rounded,
            color: C.pitch,
            dense: true,
            onPressed: () {
              _act(r.addExtraCorrect);
              app.sound.play(Sfx.correct);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GlowButton(
            label: 'اسم خاطئ',
            icon: Icons.close_rounded,
            color: C.red,
            dense: true,
            filled: false,
            onPressed: () {
              _act(r.addWrongName);
              app.sound.play(Sfx.wrong);
            },
          ),
        ),
      ]),
      const SizedBox(height: 8),
      GlowButton(
        key: const Key('resolve-auction'),
        label: 'إنهاء الوقت واحتساب النتيجة',
        icon: Icons.flag_rounded,
        dense: true,
        onPressed: _resolve,
      ),
      const SizedBox(height: 4),
      const Text('«+ اسم صحيح» للأسماء الصحيحة غير الموجودة في القائمة المرجعية بعد تحقق الحكم.',
          style: TextStyle(color: C.muted, fontSize: 11)),
      SecretAnswer(question: q),
    ];
  }
}

class _HighBid extends StatelessWidget {
  const _HighBid({required this.amount, required this.holder, required this.max, required this.decided});
  final int amount;
  final String? holder;
  final int? max;
  final bool decided;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [C.gold.withValues(alpha: .18), C.surface.withValues(alpha: .9)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.gold.withValues(alpha: decided ? 1 : .4), width: decided ? 2 : 1),
        ),
        child: Row(children: [
          const Icon(Icons.gavel_rounded, color: C.gold, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(holder == null ? 'بانتظار أول مزايدة' : (decided ? 'فاز بالمزاد' : 'أعلى مزايدة'),
                  style: const TextStyle(color: C.muted, fontSize: 13)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(holder ?? '—',
                    key: ValueKey(holder),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              if (max != null) Text('الحد الأعلى: $max', style: const TextStyle(color: C.muted, fontSize: 11)),
            ]),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text('$amount',
                key: ValueKey(amount),
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'Display', fontSize: 52, fontWeight: FontWeight.w700, color: C.gold)),
          ),
        ]),
      );
}

class _BidderRow extends StatelessWidget {
  const _BidderRow({
    required this.name,
    required this.color,
    required this.withdrawn,
    required this.leading,
    required this.onPlusOne,
    required this.onCustom,
    required this.onWithdraw,
    required this.index,
  });
  final String name;
  final Color color;
  final bool withdrawn, leading;
  final VoidCallback onPlusOne, onCustom, onWithdraw;
  final int index;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: withdrawn ? .45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: leading ? color.withValues(alpha: .15) : C.surface.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: leading ? color : C.line),
          ),
          child: Row(children: [
            Container(width: 6, height: 30, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(withdrawn ? '$name (انسحب)' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            FilledButton.tonal(
              key: Key('bid1-$name'),
              onPressed: withdrawn ? null : onPlusOne,
              child: const Text('+1'),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: Key('bidx-$name'),
              tooltip: 'مزايدة بعدد',
              onPressed: withdrawn ? null : onCustom,
              icon: const Icon(Icons.dialpad_rounded, color: C.gold),
            ),
            TextButton(
              key: Key('withdraw-$name'),
              onPressed: leading ? null : onWithdraw,
              child: Text(withdrawn ? 'عودة' : 'انسحاب', style: TextStyle(color: withdrawn ? C.pitch : C.red)),
            ),
          ]),
        ),
      );
}

class _ItemsList extends StatelessWidget {
  const _ItemsList({required this.q, required this.r, required this.open, required this.onToggle, required this.onTap});
  final Question q;
  final AuctionRound r;
  final bool open;
  final VoidCallback onToggle;
  final void Function(int) onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: Column(children: [
          ListTile(
            key: const Key('toggle-items'),
            leading: Icon(open ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: C.gold),
            title: Text('القائمة المرجعية للحكم (${q.items.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(q.itemsExhaustive ? 'قائمة كاملة' : 'قائمة مرجعية — قد توجد إجابات صحيحة أخرى',
                style: const TextStyle(color: C.muted, fontSize: 12)),
            onTap: onToggle,
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (i, item) in q.items.indexed)
                  FilterChip(
                    key: Key('item-$i'),
                    label: Text(item.name),
                    tooltip: item.aliases.join(' / '),
                    selected: r.namedItems.contains(i),
                    selectedColor: C.pitch.withValues(alpha: .3),
                    checkmarkColor: C.pitch,
                    onSelected: r.phase == AuctionPhase.answering ? (_) => onTap(i) : null,
                  ),
              ]),
            ),
        ]),
      );
}
