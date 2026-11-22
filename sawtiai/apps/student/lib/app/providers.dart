import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/repository.dart';
import '../logic/stats.dart';
import '../services/backend.dart';
import '../services/notifications.dart';

/// Overridden in main() / tests with real instances.
final repositoryProvider = ChangeNotifierProvider<Repository>((ref) => throw UnimplementedError());
final backendProvider = ChangeNotifierProvider<Backend>((ref) => throw UnimplementedError());
final notificationsProvider = Provider<NotificationService>((ref) => throw UnimplementedError());

final statsProvider = Provider<Stats>((ref) {
  final r = ref.watch(repositoryProvider);
  return Stats(tasks: r.tasks, logs: r.studyLogs, sessions: r.sessions, now: r.now());
});
