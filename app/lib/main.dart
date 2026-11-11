import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'theme.dart';
import 'ui/screens/auth_screens.dart';
import 'ui/screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.boot();
  runApp(GeneratorOsApp(state: state));
}

class GeneratorOsApp extends StatelessWidget {
  final AppState state;
  const GeneratorOsApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Generator OS',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar', 'IQ'),
          supportedLocales: const [Locale('ar', 'IQ'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          // Arabic locale makes the whole app right-to-left.
          home: !state.initialized
              ? const SetupScreen()
              : state.session == null
              ? const LoginScreen()
              : const HomeShell(),
        ),
      ),
    );
  }
}
