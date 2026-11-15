import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Full-screen elimination moment: red flash, shake, the name struck out.
Future<void> showElimination(BuildContext context, String name) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'eliminated',
    barrierColor: Colors.black.withValues(alpha: .7),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, _, _) => _Elimination(name: name),
  );
}

class _Elimination extends StatefulWidget {
  const _Elimination({required this.name});
  final String name;
  @override
  State<_Elimination> createState() => _EliminationState();
}

class _EliminationState extends State<_Elimination> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          final shake = t < .3 ? sin(t * 90) * 14 * (1 - t / .3) : 0.0;
          final strike = ((t - .25) / .25).clamp(0.0, 1.0);
          return Stack(fit: StackFit.expand, children: [
            IgnorePointer(child: ColoredBox(color: C.red.withValues(alpha: max(0, .45 - t * 1.4)))),
            Center(
              child: Transform.translate(
                offset: Offset(shake, 0),
                child: Transform.scale(
                  scale: 1.6 - .6 * Curves.easeOutBack.transform(min(1, t * 3)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.block_rounded, color: C.red, size: 90),
                      const SizedBox(height: 10),
                      const Text('إقصاء!',
                          style: TextStyle(
                              color: C.red,
                              fontSize: 54,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(color: C.red, blurRadius: 30)])),
                      const SizedBox(height: 8),
                      Stack(alignment: Alignment.center, children: [
                        Text(widget.name,
                            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700)),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: strike,
                            child: Center(child: Container(height: 5, color: C.red)),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}

/// Short centred flash (correct / wrong) over the current screen.
void flashVerdict(BuildContext context, {required bool correct, String? text}) {
  final overlay = Overlay.of(context);
  late OverlayEntry e;
  e = OverlayEntry(
    builder: (_) => _Verdict(correct: correct, text: text, onDone: () => e.remove()),
  );
  overlay.insert(e);
}

class _Verdict extends StatefulWidget {
  const _Verdict({required this.correct, this.text, required this.onDone});
  final bool correct;
  final String? text;
  final VoidCallback onDone;
  @override
  State<_Verdict> createState() => _VerdictState();
}

class _VerdictState extends State<_Verdict> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.correct ? C.pitch : C.red;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          final o = (t < .7 ? 1.0 : 1 - (t - .7) / .3).clamp(0.0, 1.0);
          return Stack(fit: StackFit.expand, children: [
            ColoredBox(color: col.withValues(alpha: .18 * o)),
            Center(
              child: Opacity(
                opacity: o,
                child: Transform.scale(
                  scale: .6 + .4 * Curves.elasticOut.transform(min(1, t * 1.6)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(widget.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: col, size: 120, shadows: [Shadow(color: col, blurRadius: 40)]),
                      if (widget.text != null)
                        Text(widget.text!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: col, fontSize: 28, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Confetti burst for the winner screen.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.count = 140});
  final int count;
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  final _rnd = Random(11);
  late final List<_Piece> _pieces = List.generate(
    widget.count,
    (_) => _Piece(
      x: _rnd.nextDouble(),
      delay: _rnd.nextDouble(),
      speed: .5 + _rnd.nextDouble() * .8,
      drift: (_rnd.nextDouble() - .5) * .3,
      spin: (_rnd.nextDouble() - .5) * 12,
      color: [C.gold, C.pitch, C.cyan, C.red, C.violet, Colors.white][_rnd.nextInt(6)],
      w: 5 + _rnd.nextDouble() * 6,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_pieces, _c.value), size: Size.infinite),
          ),
        ),
      );
}

class _Piece {
  _Piece({required this.x, required this.delay, required this.speed, required this.drift, required this.spin, required this.color, required this.w});
  final double x, delay, speed, drift, spin, w;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final c in pieces) {
      final life = (t * c.speed + c.delay) % 1.0;
      final x = (c.x + c.drift * life + sin(life * 12 + c.x * 9) * .02) * size.width;
      final y = (life * 1.15 - .1) * size.height;
      p.color = c.color.withValues(alpha: .9);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(life * c.spin);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: c.w, height: c.w * .5), p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => o.t != t;
}
