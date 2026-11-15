import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'services/controller.dart';
import 'theme.dart';

/// Gives every screen access to the controller and rebuilds listeners on
/// change.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Access without subscribing (inside callbacks).
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class HhkkllApp extends StatelessWidget {
  const HhkkllApp({super.key, required this.controller, this.skipIntro = false});
  final AppController controller;
  final bool skipIntro;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'HHKKLL',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: _Root(skipIntro: skipIntro),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({required this.skipIntro});
  final bool skipIntro;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _introDone = false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final showIntro = !widget.skipIntro && !_introDone && (!c.ready || c.settings.showIntro);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      child: showIntro
          ? IntroScreen(
              key: const ValueKey('intro'),
              sound: c.sound,
              onDone: () => setState(() => _introDone = true),
            )
          : !c.ready
              ? const ColoredBox(color: C.bg, child: Center(child: CircularProgressIndicator()))
              : const HomeScreen(key: ValueKey('home')),
    );
  }
}
