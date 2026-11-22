import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// The Sawti AI mark: a gradient tile with stylised sound bars.
class SawtiLogo extends StatelessWidget {
  const SawtiLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: SawtiColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(color: SawtiColors.deepPurple.withValues(alpha: 0.45), blurRadius: size * 0.4, offset: Offset(0, size * 0.1)),
        ],
      ),
      child: CustomPaint(painter: _BarsPainter()),
    );
  }
}

class _BarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    const heights = [0.28, 0.52, 0.78, 0.52, 0.28];
    final w = s.width * 0.09;
    final gap = s.width * 0.055;
    final total = heights.length * w + (heights.length - 1) * gap;
    var x = (s.width - total) / 2;
    final paint = Paint()..color = Colors.white;
    for (final h in heights) {
      final bh = s.height * h * 0.75;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (s.height - bh) / 2, w, bh), Radius.circular(w / 2)),
        paint,
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Page background with the brand gradient.
class SawtiBackground extends StatelessWidget {
  const SawtiBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: context.isDark ? SawtiColors.bgGradientDark : SawtiColors.bgGradientLight),
        child: child,
      );
}

/// Standard page scaffold with background, max width for tablets, safe area.
class SawtiScaffold extends StatelessWidget {
  const SawtiScaffold({super.key, required this.title, required this.body, this.actions, this.bottom});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return SawtiBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: body),
          ),
        ),
        bottomNavigationBar: bottom,
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.gradient});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final border = context.isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? context.cardColor.withValues(alpha: context.isDark ? 0.85 : 1) : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: border),
            boxShadow: context.isDark
                ? null
                : [BoxShadow(color: SawtiColors.deepPurple.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.icon, this.onPressed, this.loading = false, this.expanded = true});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
        else if (icon != null)
          Icon(icon, color: Colors.white),
        if (icon != null || loading) const SizedBox(width: 10),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onPressed : null,
            child: Ink(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(gradient: SawtiColors.brandGradient, borderRadius: BorderRadius.circular(18)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, required this.icon, this.onPressed, this.color});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: onPressed == null ? null : c),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: c,
        side: BorderSide(color: c.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class ServerStatusPill extends StatelessWidget {
  const ServerStatusPill({super.key, required this.status, this.onTap});
  final ServerStatus status;
  final VoidCallback? onTap;

  (Color, String, IconData) _look() {
    switch (status.state) {
      case ConnectionState2.online:
        return switch (status.engineState) {
          'ready' => (SawtiColors.success, 'الخادم متصل وجاهز', Icons.cloud_done_rounded),
          'loading' || 'not_loaded' => (SawtiColors.warning, 'الخادم متصل — المحرك يُحمَّل', Icons.hourglass_top_rounded),
          _ => (SawtiColors.danger, 'المحرك متوقف على الخادم', Icons.error_outline_rounded),
        };
      case ConnectionState2.waking:
        return (SawtiColors.warning, 'الخادم يستيقظ من السكون...', Icons.bedtime_rounded);
      case ConnectionState2.checking:
      case ConnectionState2.unknown:
        return (SawtiColors.textMuted, 'جارٍ فحص الخادم...', Icons.sync_rounded);
      case ConnectionState2.notConfigured:
        return (SawtiColors.textMuted, 'الخادم غير مربوط', Icons.link_off_rounded);
      case ConnectionState2.unauthorized:
        return (SawtiColors.danger, 'مفتاح الوصول غير صحيح', Icons.key_off_rounded);
      case ConnectionState2.offline:
        return (SawtiColors.danger, 'غير متصل بالخادم', Icons.cloud_off_rounded);
      case ConnectionState2.error:
        return (SawtiColors.danger, 'خطأ في الخادم', Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _look();
    return Semantics(
      label: 'حالة الخادم: $label',
      button: onTap != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.color = SawtiColors.warning, this.icon = Icons.info_outline_rounded, this.action});
  final String text;
  final Color color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
          ?action,
        ]),
      );
}

/// Live recording waveform: newest level on the leading (right in RTL) edge.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({super.key, required this.levels, this.height = 90, this.active = true});
  final List<double> levels;
  final double height;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(painter: _WavePainter(levels, active, context.isDark)),
        ),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.active, this.dark);
  final List<double> levels;
  final bool active;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 4.0, gap = 3.0;
    final n = (size.width / (barW + gap)).floor();
    final data = levels.length > n ? levels.sublist(levels.length - n) : levels;
    final paint = Paint()
      ..shader = SawtiColors.brandGradient.createShader(Offset.zero & size)
      ..strokeCap = StrokeCap.round;
    final idle = Paint()..color = dark ? Colors.white12 : Colors.black12;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final x = size.width - (i + 1) * (barW + gap);
      final idx = data.length - 1 - i;
      final v = idx >= 0 ? data[idx] : 0.0;
      final h = math.max(3.0, v * size.height * 0.95);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + barW / 2, mid), width: barW, height: h), const Radius.circular(2)),
        idx >= 0 && active ? paint : idle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.levels.length != levels.length || old.active != active || (levels.isNotEmpty && old.levels.last != levels.last);
}

class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final c = level > 0.92 ? SawtiColors.danger : level > 0.15 ? SawtiColors.success : SawtiColors.warning;
    return Semantics(
      label: 'مستوى الصوت',
      value: '${(level * 100).round()}٪',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: level.clamp(0, 1),
          minHeight: 8,
          color: c,
          backgroundColor: context.isDark ? Colors.white10 : Colors.black12,
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String body, String ok = 'حذف', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: SawtiColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? SawtiColors.danger : null,
    ));
}
