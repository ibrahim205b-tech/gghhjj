import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Deep navy background with soft blurred ambient lights (blue, cyan, warm).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [Color(0xFF0E2340), EnjazColors.navy, EnjazColors.navyDeep]
                  : const [Color(0xFFDCE9FB), Color(0xFFEFF3FA), Color(0xFFF7F9FD)],
            ),
          ),
        ),
      ),
      // Static blurred glow blobs (painted once; cheap).
      const _Glow(alignment: Alignment(-1.1, -0.85), color: EnjazColors.blueGlow, size: 320),
      const _Glow(alignment: Alignment(1.2, -0.3), color: EnjazColors.cyanGlow, size: 260),
      const _Glow(alignment: Alignment(-1.0, 0.55), color: EnjazColors.warmGlow, size: 200, opacity: 0.22),
      Positioned.fill(child: child),
    ]);
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.alignment, required this.color, required this.size, this.opacity = 0.35});
  final Alignment alignment;
  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final o = context.isDark ? opacity : opacity * 0.45;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: o), color.withValues(alpha: 0)]),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass card. [blur] is opt-in (BackdropFilter is expensive in lists).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.blur = false,
    this.radius = EnjazRadii.card,
    this.gradient,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool blur;
  final double radius;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    Widget body = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? EnjazColors.glassFill(dark) : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: EnjazColors.glassBorder(dark)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (blur) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: body),
      );
    }
    return body;
  }
}

/// Pill button with gradient fill and a soft glow.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.gradient,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 54,
  });
  final String label;
  final Gradient gradient;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final glow = (gradient as LinearGradient).colors.first;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EnjazRadii.button),
            boxShadow: enabled
                ? [BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(EnjazRadii.button),
              onTap: enabled ? onPressed : null,
              child: Ink(
                decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(EnjazRadii.button)),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (loading)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      else if (icon != null)
                        Icon(icon, color: Colors.white, size: 20),
                      if (loading || icon != null) const SizedBox(width: 8),
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                      ),
                    ]),
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

/// Rounded progress bar with the lime gradient and an inline percentage.
class EnjazProgressBar extends StatelessWidget {
  const EnjazProgressBar({super.key, required this.value, this.height = 26, this.showLabel = true, this.gradient});
  final double value;
  final double height;
  final bool showLabel;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(v * 100).round()}%',
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth * v;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: context.isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(height),
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: w),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, width, _) => Container(
                width: v == 0 ? 0 : width.clamp(height, c.maxWidth),
                height: height,
                alignment: AlignmentDirectional.centerEnd,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  gradient: gradient ?? EnjazColors.progressGradient,
                  borderRadius: BorderRadius.circular(height),
                ),
                child: showLabel && v >= 0.12
                    ? Text('${(v * 100).round()}%',
                        style: const TextStyle(color: Color(0xFF14301A), fontSize: 12, fontWeight: FontWeight.w800))
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Square glass stat tile (icon, big number, caption) as in the reference design.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.iconColor, required this.value, required this.label, this.onTap});
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      radius: EnjazRadii.tile,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(height: 10),
        FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.mutedText)),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700))),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!, style: TextStyle(color: context.mutedText))),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: context.mutedText.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.mutedText, height: 1.6)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.filled = false});
  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(EnjazRadii.chip),
        ),
        child: Text(label,
            style: TextStyle(color: filled ? Colors.white : color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

/// Standard page: ambient background, transparent app bar, max width for tablets.
class EnjazPage extends StatelessWidget {
  const EnjazPage({super.key, required this.title, required this.body, this.actions, this.fab});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;

  @override
  Widget build(BuildContext context) => AmbientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(title), actions: actions),
          floatingActionButton: fab,
          body: SafeArea(
            top: false,
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body)),
          ),
        ),
      );
}

/// The ENJAZ mark: an upward step/arrow inside a glowing rounded tile.
class EnjazLogo extends StatelessWidget {
  const EnjazLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: EnjazColors.brandGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [BoxShadow(color: EnjazColors.cyan.withValues(alpha: 0.4), blurRadius: size * 0.45)],
        ),
        child: CustomPaint(painter: _StepsPainter()),
      );
}

class _StepsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Rising steps ending in an arrow: "your step today builds your future".
    final path = Path()
      ..moveTo(s.width * 0.20, s.height * 0.72)
      ..lineTo(s.width * 0.38, s.height * 0.72)
      ..lineTo(s.width * 0.38, s.height * 0.56)
      ..lineTo(s.width * 0.54, s.height * 0.56)
      ..lineTo(s.width * 0.54, s.height * 0.38)
      ..lineTo(s.width * 0.80, s.height * 0.38);
    canvas.drawPath(path, p);
    final arrow = Path()
      ..moveTo(s.width * 0.69, s.height * 0.27)
      ..lineTo(s.width * 0.80, s.height * 0.38)
      ..lineTo(s.width * 0.69, s.height * 0.49);
    canvas.drawPath(arrow, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void showEnjazSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? EnjazColors.danger : null));
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String body, required String ok,
    required String cancel, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(height: 1.6)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: EnjazColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}
