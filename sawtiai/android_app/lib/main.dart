import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/splash.dart';
import 'services/storage.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  final state = createAppState();
  runApp(SawtiApp(state: state));
}

AppState createAppState({SecretStore? secrets, AppDirs? dirs}) {
  final d = dirs ?? AppDirs();
  return AppState(
    settingsStore: SettingsStore(secrets: secrets),
    voiceRepo: VoiceRepository(d),
    libraryRepo: LibraryRepository(d),
    dirs: d,
  );
}

class SawtiApp extends StatefulWidget {
  const SawtiApp({super.key, required this.state, this.splashDuration = const Duration(milliseconds: 1900)});
  final AppState state;
  final Duration splashDuration;

  @override
  State<SawtiApp> createState() => _SawtiAppState();
}

class _SawtiAppState extends State<SawtiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && widget.state.loaded) widget.state.refreshServerStatus();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: widget.state,
      child: Selector<AppState, ThemeMode>(
        selector: (_, s) => s.themeMode,
        builder: (_, mode, _) => MaterialApp(
          title: 'صوتي AI',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SplashScreen(duration: widget.splashDuration),
        ),
      ),
    );
  }
}
