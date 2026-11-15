import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../theme.dart';
import 'common.dart';

class AnimatedScore extends StatelessWidget {
  const AnimatedScore(this.value, {super.key, this.style});
  final int value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value.toDouble()),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(
          v.round().toString(),
          textDirection: TextDirection.ltr,
          style: style ??
              const TextStyle(fontFamily: 'Display', fontWeight: FontWeight.w700, fontSize: 26),
        ),
      );
}

/// Ranked competition board: position, colour, score, strikes, status and
/// per-player counters.
class Scoreboard extends StatelessWidget {
  const Scoreboard({
    super.key,
    required this.session,
    this.compact = false,
    this.highlight,
    this.onTap,
  });
  final GameSession session;
  final bool compact;
  final String? highlight;
  final void Function(PlayerState)? onTap;

  @override
  Widget build(BuildContext context) {
    final ranking = session.ranking;
    final colorIndex = {for (final (i, p) in session.players.indexed) p.id: i};
    return Column(
      children: [
        for (final (pos, p) in ranking.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PlayerRow(
              key: ValueKey('score-${p.id}'),
              pos: pos + 1,
              p: p,
              color: C.player(colorIndex[p.id]!),
              limit: session.settings.strikeLimit,
              compact: compact,
              highlighted: p.id == highlight,
              onTap: onTap == null ? null : () => onTap!(p),
            ),
          ),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    super.key,
    required this.pos,
    required this.p,
    required this.color,
    required this.limit,
    required this.compact,
    required this.highlighted,
    this.onTap,
  });
  final int pos;
  final PlayerState p;
  final Color color;
  final int limit;
  final bool compact;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final out = p.eliminated;
    final medal = switch (pos) { 1 => C.gold, 2 => const Color(0xFFC9D1E0), 3 => const Color(0xFFD08A4E), _ => C.muted };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: .18) : C.surface.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlighted ? color : (out ? C.red.withValues(alpha: .35) : C.line), width: highlighted ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Opacity(
          opacity: out ? .5 : 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 12),
            child: Row(children: [
              SizedBox(
                width: 26,
                child: Text('$pos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Display', color: medal, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              const SizedBox(width: 6),
              Container(width: 6, height: compact ? 28 : 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 15 : 17,
                            decoration: out ? TextDecoration.lineThrough : null,
                            decorationColor: C.red,
                            decorationThickness: 2,
                          )),
                    ),
                    if (out) ...[
                      const SizedBox(width: 6),
                      const _Badge('مُقصى', C.red),
                    ],
                  ]),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, children: [
                      _Stat(Icons.check_circle_rounded, C.pitch, p.correct, 'صحيحة'),
                      _Stat(Icons.cancel_rounded, C.red, p.wrong, 'خاطئة'),
                      _Stat(Icons.gavel_rounded, C.gold, p.auctionsWon, 'مزاد'),
                      _Stat(Icons.notifications_active_rounded, C.cyan, p.firstBuzzes, 'جرس'),
                    ]),
                  ],
                ]),
              ),
              StrikeMarks(strikes: p.strikes, limit: limit, size: compact ? 13 : 16),
              const SizedBox(width: 12),
              AnimatedScore(p.score,
                  style: TextStyle(
                      fontFamily: 'Display', fontWeight: FontWeight.w700, fontSize: compact ? 22 : 28, color: p.score < 0 ? C.red : C.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.color, this.n, this.tip);
  final IconData icon;
  final Color color;
  final int n;
  final String tip;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text('$n', style: const TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );
}
