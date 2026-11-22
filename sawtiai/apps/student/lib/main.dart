import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/local_db.dart';
import 'data/repository.dart';
import 'services/backend.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  await Backend.initialize();
  final repo = Repository(await LocalDb.open());
  await repo.load();
  final backend = Backend(repo)..start();
  final notifications = NotificationService();
  await notifications.init();
  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWith((ref) => repo),
      backendProvider.overrideWith((ref) => backend),
      notificationsProvider.overrideWithValue(notifications),
    ],
    child: const EnjazApp(),
  ));
}
