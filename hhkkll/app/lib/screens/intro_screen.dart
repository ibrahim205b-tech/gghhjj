import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opening credits — part of the HHKKLL identity.
const introLine1 = 'المطور ابراهيم تاج راسكم';
const introLine2 = 'برمجة ابراهيم البو حطة';
const introLine3 = 'استعد للمنافسة...';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.sound, required this.onDone});
  final SoundService sound;
  final VoidCallback onDone;

  static const total = Duration(milliseconds: 10400);

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: IntroScreen.total,
  );
  final List<Timer> _timers = [];
  bool _finished = false;

  double get _ms => _c.value * IntroScreen.total.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _c.forward();
    void at(int ms, Sfx s) => _timers.add(
      Timer(Duration(milliseconds: ms), () => widget.sound.play(s)),
    );
    at(0, Sfx.introBoom);
    at(700, Sfx.introWhoosh);
    at(3900, Sfx.introWhoosh);
    at(6700, Sfx.introRise);
    at(7600, Sfx.introHit);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    for (final t in _timers) {
      t.cancel();
    }
    widget.onDone();
  }

  void _skip() {
    widget.sound.stopAll();
    _finish();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _c.dispose();
    super.dispose();
  }

  /// 0→1 progress of [ms] inside the window [a, b].
  double _p(int a, int b) => ((_ms - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final size = MediaQuery.sizeOf(context);
          final short = min(size.width, size.height);
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _CinemaLight(_ms)),
              // Line 1
              _CreditLine(
                text: introLine1,
                inP: _p(600, 2200),
                sweepP: _p(1200, 3200),
                outP: _p(3500, 4100),
                fontSize: short * .075,
                color: Colors.white,
              ),
              // Line 2
              _CreditLine(
                text: introLine2,
                inP: _p(3900, 5400),
                sweepP: _p(4500, 6400),
                outP: _p(6500, 7100),
                fontSize: short * .068,
                color: C.gold,
              ),
              // Logo + tagline
              _LogoReveal(
                inP: _p(7550, 8350),
                flashP: _p(7550, 8150),
                tagP: _p(8500, 9200),
                outP: _p(9900, 10400),
                size: short * .17,
              ),
              // Letterbox bars (cinema framing).
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: size.height * .09 * (1 - _p(9900, 10400)),
                  color: Colors.black,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: size.height * .09 * (1 - _p(9900, 10400)),
                  color: Colors.black,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextButton.icon(
                      key: const Key('skip-intro'),
                      onPressed: _skip,
                      icon: const Icon(
                        Icons.skip_previous_rounded,
                        color: C.muted,
                      ),
                      label: const Text(
                        'تخطي',
                        style: TextStyle(color: C.muted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CreditLine extends StatelessWidget {
  const _CreditLine({
    required this.text,
    required this.inP,
    required this.sweepP,
    required this.outP,
    required this.fontSize,
    required this.color,
  });
  final String text;
  final double inP, sweepP, outP, fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (inP <= 0 || outP >= 1) return const SizedBox.shrink();
    final e = Curves.easeOutCubic.transform(inP);
    final o = Curves.easeInCubic.transform(outP);
    final opacity = (e * (1 - o)).clamp(0.0, 1.0);
    final blur = 14 * (1 - e) + 10 * o;
    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, -30 * o),
          child: Transform.scale(
            scale: 1.12 - .12 * e + .06 * o,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) {
                  final p = sweepP * 1.6 - .3;
                  return LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      color.withValues(alpha: .55),
                      color,
                      Colors.white,
                      color,
                      color.withValues(alpha: .55),
                    ],
                    stops: [
                      0,
                      (p - .18).clamp(0, 1),
                      p.clamp(0, 1),
                      (p + .18).clamp(0, 1),
                      1,
                    ],
                  ).createShader(r);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6 * (1 - e),
                        height: 1.5,
                        shadows: [
                          Shadow(
                            color: color.withValues(alpha: .7),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoReveal extends StatelessWidget {
  const _LogoReveal({
    required this.inP,
    required this.flashP,
    required this.tagP,
    required this.outP,
    required this.size,
  });
  final double inP, flashP, tagP, outP, size;

  @override
  Widget build(BuildContext context) {
    if (inP <= 0) return const SizedBox.shrink();
    final e = Curves.easeOutBack.transform(inP);
    final fade = 1 - Curves.easeIn.transform(outP);
    return Opacity(
      opacity: fade.clamp(0.0, 1.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // White flash on impact.
          IgnorePointer(
            child: ColoredBox(
              color: Colors.white.withValues(
                alpha: (1 - flashP) * .55 * (flashP > 0 ? 1 : 0),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 2.4 - 1.4 * e,
                  child: Opacity(
                    opacity: inP,
                    child: Wordmark(size: size),
                  ),
                ),
                SizedBox(height: size * .45),
                Opacity(
                  opacity: tagP,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - tagP)),
                    child: Text(
                      introLine3,
                      style: TextStyle(
                        color: C.text,
                        fontSize: size * .24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        shadows: [
                          Shadow(
                            color: C.pitch.withValues(alpha: .6),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Spotlight cone + drifting dust that follow the timeline.
class _CinemaLight extends CustomPainter {
  _CinemaLight(this.ms);
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final on = (ms / 900).clamp(0.0, 1.0);
    final cx = w / 2 + sin(ms / 1400) * w * .08;
    final spot = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: .10 * on),
              Colors.white.withValues(alpha: .03 * on),
              Colors.transparent,
            ],
            stops: const [0, .45, 1],
          ).createShader(
            Rect.fromCircle(center: Offset(cx, h * .48), radius: w * .75),
          );
    canvas.drawRect(Offset.zero & size, spot);
    // Gold glow building up before the logo.
    final g =
        ((ms - 6700) / 900).clamp(0.0, 1.0) *
        (1 - ((ms - 9900) / 500).clamp(0.0, 1.0));
    if (g > 0) {
      final glow = Paint()
        ..shader =
            RadialGradient(
              colors: [
                C.gold.withValues(alpha: .22 * g),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: Offset(w / 2, h / 2), radius: w * .7),
            );
      canvas.drawRect(Offset.zero & size, glow);
      // Light rays.
      final rays = Paint()..color = C.gold.withValues(alpha: .05 * g);
      for (var i = 0; i < 12; i++) {
        final a = i * pi / 6 + ms / 4000;
        final path = Path()
          ..moveTo(w / 2, h / 2)
          ..lineTo(
            w / 2 + cos(a - .05) * w * 1.2,
            h / 2 + sin(a - .05) * w * 1.2,
          )
          ..lineTo(
            w / 2 + cos(a + .05) * w * 1.2,
            h / 2 + sin(a + .05) * w * 1.2,
          )
          ..close();
        canvas.drawPath(path, rays);
      }
    }
    // Dust particles.
    final rnd = Random(3);
    final dust = Paint();
    for (var i = 0; i < 60; i++) {
      final x = (rnd.nextDouble() * w + ms * (rnd.nextDouble() - .5) * .02) % w;
      final y = (rnd.nextDouble() * h - ms * rnd.nextDouble() * .015) % h;
      dust.color = Colors.white.withValues(
        alpha: .05 + .12 * rnd.nextDouble() * on,
      );
      canvas.drawCircle(Offset(x, y), .6 + rnd.nextDouble() * 1.4, dust);
    }
  }

  @override
  bool shouldRepaint(_CinemaLight o) => o.ms != ms;
}
