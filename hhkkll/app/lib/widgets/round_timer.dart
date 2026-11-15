import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';

/// Referee-controlled countdown (start / pause / reset) with tick sounds in
/// the last seconds.
class RoundTimerController extends ChangeNotifier {
  RoundTimerController({required int seconds, required this.sound, this.onFinished})
      : _total = Duration(seconds: seconds);

  final SoundService sound;
  VoidCallback? onFinished;
  Duration _total;
  final Stopwatch _sw = Stopwatch();
  Duration _base = Duration.zero;
  Timer? _ticker;
  int _lastWhole = -1;

  Duration get total => _total;
  bool get running => _sw.isRunning;
  Duration get elapsed => _base + _sw.elapsed;
  Duration get remaining {
    final r = _total - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  bool get finished => remaining == Duration.zero;
  double get fraction => _total.inMilliseconds == 0 ? 0 : remaining.inMilliseconds / _total.inMilliseconds;
  int get secondsLeft => (remaining.inMilliseconds / 1000).ceil();

  void start() {
    if (running || finished) return;
    _sw.start();
    _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _sw.stop();
    notifyListeners();
  }

  void reset({int? seconds}) {
    _sw
      ..stop()
      ..reset();
    _base = Duration.zero;
    if (seconds != null) _total = Duration(seconds: seconds);
    _lastWhole = -1;
    notifyListeners();
  }

  void _tick() {
    if (!running) return;
    final s = secondsLeft;
    if (s != _lastWhole) {
      _lastWhole = s;
      if (s <= 5 && s > 0) sound.play(s == 1 ? Sfx.tickLast : Sfx.tick);
    }
    if (finished) {
      _base = _total;
      _sw
        ..stop()
        ..reset();
      sound.play(Sfx.wrong);
      onFinished?.call();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class TimerRing extends StatelessWidget {
  const TimerRing({super.key, required this.controller, this.size = 120, this.color = C.gold, this.showControls = true});
  final RoundTimerController controller;
  final double size;
  final Color color;
  final bool showControls;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final f = controller.fraction;
          final urgent = controller.secondsLeft <= 5 && controller.running;
          final col = urgent ? C.red : color;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _RingPainter(f, col),
                child: Center(
                  child: AnimatedScale(
                    scale: urgent ? 1.12 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Text('${controller.secondsLeft}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontFamily: 'Display',
                            fontWeight: FontWeight.w700,
                            fontSize: size * .34,
                            color: col,
                            shadows: [Shadow(color: col.withValues(alpha: .7), blurRadius: 18)])),
                  ),
                ),
              ),
            ),
            if (showControls) ...[
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: const Key('timer-toggle'),
                  tooltip: controller.running ? 'إيقاف المؤقت' : 'تشغيل المؤقت',
                  onPressed: controller.finished ? null : (controller.running ? controller.pause : controller.start),
                  icon: Icon(controller.running ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                      color: col, size: 34),
                ),
                IconButton(
                  key: const Key('timer-reset'),
                  tooltip: 'إعادة المؤقت',
                  onPressed: () => controller.reset(),
                  icon: const Icon(Icons.replay_rounded, color: C.muted, size: 28),
                ),
              ]),
            ],
          ]);
        },
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color);
  final double f;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 6;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()
      ..color = C.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      2 * pi * f,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.f != f || o.color != color;
}
