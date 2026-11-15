import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../app.dart';
import '../services/controller.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';
import 'home_screen.dart';
import 'new_game_screen.dart';

/// Winner announcement: podium rising, crown, confetti, full statistics.
class FinalScreen extends StatefulWidget {
  const FinalScreen({super.key, required this.record});
  final MatchRecord record;
  @override
  State<FinalScreen> createState() => _FinalScreenState();
}

class _FinalScreenState extends State<FinalScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).sound.play(Sfx.winner));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _p(double a, double b) => ((_c.value - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final players = widget.record.players;
    final top = players.take(3).toList();
    return Scaffold(
      body: StageBackground(
        child: Stack(children: [
          const Positioned.fill(child: Confetti()),
          SafeArea(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                children: [
                  Opacity(
                    opacity: _p(.0, .2),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.emoji_events_rounded, color: C.gold, size: 26),
                      SizedBox(width: 8),
                      Text('بطل المنافسة',
                          style: TextStyle(color: C.gold, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  if (top.isNotEmpty)
                    Transform.scale(
                      scale: .4 + .6 * Curves.elasticOut.transform(_p(.55, 1)),
                      child: Opacity(
                        opacity: _p(.55, .7),
                        child: Center(
                          child: Text(top.first.name,
                              key: const Key('winner-name'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w700,
                                  shadows: [Shadow(color: C.gold, blurRadius: 30)])),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 290,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (top.length > 1) Expanded(child: _Podium(p: top[1], place: 2, h: 120 * _p(.2, .45))),
                      Expanded(child: _Podium(p: top[0], place: 1, h: 170 * _p(.4, .65), crown: _p(.6, .8))),
                      if (top.length > 2) Expanded(child: _Podium(p: top[2], place: 3, h: 90 * _p(.1, .35))),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  Opacity(opacity: _p(.7, 1), child: _StatsTable(players: players)),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: GlowButton(
                        key: const Key('play-again'),
                        label: 'لعبة جديدة',
                        icon: Icons.replay_rounded,
                        onPressed: () => Navigator.of(context).pushReplacement(fadeRoute(const NewGameScreen())),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlowButton(
                        label: 'الرئيسية',
                        icon: Icons.home_rounded,
                        filled: false,
                        color: C.text,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.p, required this.place, required this.h, this.crown = 0});
  final PlayerState p;
  final int place;
  final double h;
  final double crown;
  @override
  Widget build(BuildContext context) {
    final col = switch (place) { 1 => C.gold, 2 => const Color(0xFFC9D1E0), _ => const Color(0xFFD08A4E) };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (place == 1)
          Opacity(
            opacity: crown,
            child: Transform.translate(
              offset: Offset(0, -20 * (1 - crown)),
              child: const Icon(Icons.workspace_premium_rounded, color: C.gold, size: 40, shadows: [Shadow(color: C.gold, blurRadius: 24)]),
            ),
          ),
        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${p.score}', textDirection: TextDirection.ltr, style: TextStyle(fontFamily: 'Display', color: col, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Container(
          height: h,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [col.withValues(alpha: .85), col.withValues(alpha: .25)]),
            boxShadow: [BoxShadow(color: col.withValues(alpha: .35), blurRadius: 20)],
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: h > 30
              ? Text('$place', style: const TextStyle(fontFamily: 'Display', fontSize: 30, fontWeight: FontWeight.w700, color: Colors.black))
              : null,
        ),
      ]),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.players});
  final List<PlayerState> players;
  @override
  Widget build(BuildContext context) {
    const h = TextStyle(color: C.muted, fontSize: 11);
    Widget cell(String t, {TextStyle? style, bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Text(t, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: head ? h : style),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Table(
          columnWidths: const {0: FixedColumnWidth(24), 1: FlexColumnWidth(2.4)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(horizontalInside: BorderSide(color: C.line)),
          children: [
            TableRow(children: [
              cell('#', head: true),
              const Text('اللاعب', style: h),
              cell('النقاط', head: true),
              cell('صحيحة', head: true),
              cell('خاطئة', head: true),
              cell('Strike', head: true),
              cell('مزاد', head: true),
              cell('جرس', head: true),
            ]),
            for (final (i, p) in players.indexed)
              TableRow(children: [
                cell('${i + 1}', style: const TextStyle(fontFamily: 'Display')),
                Text(p.name + (p.eliminated ? ' (مُقصى)' : ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                cell('${p.score}', style: const TextStyle(fontWeight: FontWeight.w700, color: C.gold)),
                cell('${p.correct}', style: const TextStyle(color: C.pitch)),
                cell('${p.wrong}', style: const TextStyle(color: C.red)),
                cell('${p.strikes}'),
                cell('${p.auctionsWon}'),
                cell('${p.firstBuzzes}'),
              ]),
          ],
        ),
      ),
    );
  }
}
