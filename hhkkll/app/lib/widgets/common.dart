import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../theme.dart';

/// Black stage with slowly drifting stadium light beams.
class StageBackground extends StatefulWidget {
  const StageBackground({super.key, required this.child, this.accent = C.gold});
  final Widget child;
  final Color accent;
  @override
  State<StageBackground> createState() => _StageBackgroundState();
}

class _StageBackgroundState extends State<StageBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: C.bg),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(
                painter: _BeamsPainter(_c.value, widget.accent),
              ),
            ),
          ),
          widget.child,
        ],
      );
}

class _BeamsPainter extends CustomPainter {
  _BeamsPainter(this.t, this.accent);
  final double t;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void beam(double x, double angle, Color c, double alpha) {
      final p = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * .9));
      canvas.save();
      canvas.translate(x, -20);
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(-6, 0)
        ..lineTo(6, 0)
        ..lineTo(w * .28, h * 1.1)
        ..lineTo(-w * .28, h * 1.1)
        ..close();
      canvas.drawPath(path, p);
      canvas.restore();
    }

    final s = sin(t * 2 * pi);
    beam(w * .12, -.35 + .06 * s, accent, .10);
    beam(w * .88, .35 - .06 * s, accent, .10);
    beam(w * .5, .05 * sin(t * 4 * pi), Colors.white, .045);
    // Pitch glow at the bottom.
    final g = Paint()
      ..shader = RadialGradient(
        colors: [C.pitch.withValues(alpha: .07), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(w / 2, h * 1.05), radius: w * .9));
    canvas.drawRect(Offset.zero & size, g);
  }

  @override
  bool shouldRepaint(_BeamsPainter o) => o.t != t || o.accent != accent;
}

/// Large tappable action with a glowing border.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = C.gold,
    this.filled = true,
    this.height = 58,
    this.dense = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool filled;
  final double height;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = filled ? (color.computeLuminance() > .5 ? Colors.black : Colors.white) : color;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : .38,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled && filled
              ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 18, spreadRadius: -2)]
              : null,
        ),
        child: Material(
          color: filled ? color : color.withValues(alpha: .08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: filled ? 0 : .55), width: 1.4),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: dense ? 20 : 24),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: dense ? 14 : 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The HHKKLL wordmark with a moving light sheen.
class Wordmark extends StatefulWidget {
  const Wordmark({super.key, this.size = 56, this.animate = true});
  final double size;
  final bool animate;
  @override
  State<Wordmark> createState() => _WordmarkState();
}

class _WordmarkState extends State<Wordmark> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) {
            final p = _c.value * 2.4 - .7;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [C.goldDeep, C.gold, Colors.white, C.gold, C.goldDeep],
              stops: [0, (p - .15).clamp(0, 1), p.clamp(0, 1), (p + .15).clamp(0, 1), 1],
            ).createShader(r);
          },
          child: Text(
            'HHKKLL',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: 'Display',
              fontWeight: FontWeight.w700,
              fontSize: widget.size,
              letterSpacing: widget.size * .16,
              height: 1,
              shadows: [Shadow(color: C.gold.withValues(alpha: .5), blurRadius: 24)],
            ),
          ),
        ),
      );
}

/// Section header pill: icon + Arabic + English name.
class SectionTag extends StatelessWidget {
  const SectionTag(this.category, {super.key, this.compact = false});
  final Category category;

  /// Icon + Arabic name only (narrow app bars).
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final col = C.of(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: col.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: col.withValues(alpha: .5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(C.icon(category), color: col, size: 18),
        const SizedBox(width: 6),
        Text(category.arabic, style: TextStyle(color: col, fontWeight: FontWeight.w700)),
        if (!compact) const SizedBox(width: 6),
        if (!compact)
          Text(category.english,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontFamily: 'Display', color: col.withValues(alpha: .7), fontSize: 11, letterSpacing: 1.2)),
      ]),
    );
  }
}

/// Three strike marks (✕) filled according to the count.
class StrikeMarks extends StatelessWidget {
  const StrikeMarks({super.key, required this.strikes, required this.limit, this.size = 16});
  final int strikes;
  final int limit;
  final double size;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < limit; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: i < strikes ? C.red : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: i < strikes ? C.red : C.line, width: 1.4),
                boxShadow: i < strikes
                    ? [BoxShadow(color: C.red.withValues(alpha: .6), blurRadius: 8)]
                    : null,
              ),
              child: i < strikes
                  ? Icon(Icons.close_rounded, size: size * .8, color: Colors.white)
                  : null,
            ),
        ],
      );
}

/// Hidden answer for the referee: press and hold to peek, so players
/// sharing the same screen do not see it.
class SecretAnswer extends StatefulWidget {
  const SecretAnswer({super.key, required this.question, this.revealed = false});
  final Question question;
  final bool revealed;
  @override
  State<SecretAnswer> createState() => _SecretAnswerState();
}

class _SecretAnswerState extends State<SecretAnswer> {
  bool _peek = false;
  @override
  Widget build(BuildContext context) {
    final show = _peek || widget.revealed;
    return GestureDetector(
      onLongPressStart: (_) => setState(() => _peek = true),
      onLongPressEnd: (_) => setState(() => _peek = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: show ? C.pitch.withValues(alpha: .12) : C.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: show ? C.pitch : C.line),
        ),
        child: Row(children: [
          Icon(show ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: show ? C.pitch : C.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: show
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.question.answer,
                        style: const TextStyle(
                            color: C.pitch, fontWeight: FontWeight.w700, fontSize: 17)),
                    if (widget.question.acceptedAnswers.isNotEmpty)
                      Text('مقبول أيضاً: ${widget.question.acceptedAnswers.join('، ')}',
                          style: const TextStyle(color: C.muted, fontSize: 12)),
                  ])
                : const Text('الإجابة للحكم فقط — اضغط مطولاً للإظهار',
                    style: TextStyle(color: C.muted, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

/// Verification badge shown next to a question for the referee.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge(this.q, {super.key});
  final Question q;
  @override
  Widget build(BuildContext context) {
    final v = q.verification.isVerified;
    final col = v ? C.pitch : C.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: col.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(v ? Icons.verified_rounded : Icons.menu_book_rounded, size: 14, color: col),
        const SizedBox(width: 4),
        Text(v ? 'موثّق بالتحقق الآلي' : 'منسّق يدوياً',
            style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(q.difficulty.arabic, style: const TextStyle(color: C.muted, fontSize: 11)),
      ]),
    );
  }
}

String arabicCount(int n) => n.toString();
