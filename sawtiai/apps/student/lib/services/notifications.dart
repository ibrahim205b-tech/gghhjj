import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/config.dart';
import '../data/models.dart';

/// Local reminders (study sessions, exams) work offline. Remote push uses
/// Firebase Cloud Messaging only when Firebase client options were provided
/// at build time; otherwise it is simply disabled.
class NotificationService {
  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool pushEnabled = false;

  static const _studyChannel = AndroidNotificationDetails('study', 'تذكيرات الدراسة',
      importance: Importance.high, priority: Priority.high);
  static const _examChannel = AndroidNotificationDetails('exams', 'تذكيرات الامتحانات',
      importance: Importance.high, priority: Priority.high);
  static const _generalChannel = AndroidNotificationDetails('general', 'إشعارات إنجاز',
      importance: Importance.defaultImportance);

  Future<void> init({void Function(String? payload)? onTap}) async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Baghdad'));
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
      _ready = true;
    } catch (e) {
      debugPrint('local notifications unavailable: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNow(String title, String body, {String? payload}) async {
    if (!_ready) return;
    await _local.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(android: _generalChannel));
  }

  /// Re-schedules all local reminders for the next 7 days.
  Future<void> rescheduleReminders({
    required List<StudySession> sessions,
    required List<ExamItem> exams,
    required bool studyEnabled,
    required bool examsEnabled,
    required String Function(String title) studyBody,
    required String studyTitle,
    required String examTitle,
    required String Function(String title) examBody,
  }) async {
    if (!_ready) return;
    await _local.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    var id = 1;
    if (studyEnabled) {
      for (var d = 0; d < 7; d++) {
        final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
        for (final s in sessions.where((s) => s.occursOn(day) && !s.doneOn(day))) {
          final m = minutesOf(s.startTime);
          final at = tz.TZDateTime(tz.local, day.year, day.month, day.day, m ~/ 60, m % 60);
          if (at.isBefore(now)) continue;
          await _local.zonedSchedule(
            id: id++,
            scheduledDate: at,
            title: studyTitle,
            body: studyBody(s.title ?? s.customSubject ?? ''),
            notificationDetails: const NotificationDetails(android: _studyChannel),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: 'enjaz://schedule',
          );
        }
      }
    }
    if (examsEnabled) {
      for (final e in exams) {
        final dayBefore = e.examAt.subtract(const Duration(days: 1));
        final at = tz.TZDateTime(tz.local, dayBefore.year, dayBefore.month, dayBefore.day, 18);
        if (at.isBefore(now) || at.difference(now).inDays > 60) continue;
        await _local.zonedSchedule(
          id: 50000 + (id++),
          scheduledDate: at,
          title: examTitle,
          body: examBody(e.title),
          notificationDetails: const NotificationDetails(android: _examChannel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'enjaz://exams',
        );
      }
    }
  }

  /// Initializes FCM if configured. [onToken] receives the registration id
  /// now and again whenever Firebase rotates it.
  Future<bool> initPush({void Function(RemoteMessage m)? onOpen, required void Function(String id) onToken}) async {
    if (!AppConfig.firebaseConfigured) return false;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) showNow(n.title ?? '', n.body ?? '', payload: m.data['deep_link'] as String?);
      });
      if (onOpen != null) FirebaseMessaging.onMessageOpenedApp.listen(onOpen);
      fm.onRegistered.listen(onToken);
      await fm.register();
      pushEnabled = true;
      return true;
    } catch (e) {
      debugPrint('push unavailable: $e');
      return false;
    }
  }
}
