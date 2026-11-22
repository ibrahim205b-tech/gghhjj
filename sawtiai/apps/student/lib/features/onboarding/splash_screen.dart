import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  late final _scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
  late final _fade = CurvedAnimation(parent: _c, curve: const Interval(0.4, 1, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), _go);
  }

  void _go() {
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);
    final backend = ref.read(backendProvider);
    if (backend.signedIn) backend.sync();
    context.go(repo.onboardingDone && repo.profile.complete ? '/home' : '/onboarding');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(scale: _scale, child: const EnjazLogo(size: 112)),
            const SizedBox(height: 28),
            FadeTransition(
              opacity: _fade,
              child: Column(children: [
                Text(l.appName, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                const Text('ENJAZ',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(letterSpacing: 6, color: EnjazColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                ShaderMask(
                  shaderCallback: (r) => EnjazColors.brandGradient.createShader(r),
                  child: Text(l.slogan, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
