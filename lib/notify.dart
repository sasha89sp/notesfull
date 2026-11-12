import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'desktop.dart';
import 'models.dart';
import 'store.dart';

/// Android: AlarmManager через flutter_local_notifications (без Google Play Services).
/// Windows: проверка раз в 20 секунд + собственное всплывающее окно.
class Notifier {
  static final Notifier I = Notifier._();
  Notifier._();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  Store? _store;
  Timer? _timer;
  DateTime _last = DateTime.now().subtract(const Duration(minutes: 2));
  final Set<String> _fired = {};
  bool _ready = false;

  Future<void> init(Store s) async {
    _store = s;
    s.onEventsChanged = reschedule;
    if (Platform.isAndroid) {
      tzdata.initializeTimeZones();
      await _fln.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      final a = _fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        await a?.requestNotificationsPermission();
      } catch (_) {}
      try {
        await a?.requestExactAlarmsPermission();
      } catch (_) {}
      _ready = true;
    } else if (Platform.isWindows) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    }
    await reschedule();
  }

  void _tick() {
    final s = _store;
    if (s == null) return;
    final now = DateTime.now();
    for (final e in s.events) {
      if (e.deleted || e.done) continue;
      final a = e.alarm;
      if (a == null) continue;
      if (a.isAfter(_last) && !a.isAfter(now)) {
        final key = '${e.id}:${a.millisecondsSinceEpoch}';
        if (_fired.add(key)) Desktop.I.showAlert(e);
      }
    }
    _last = now;
  }

  Future<void> reschedule() async {
    final s = _store;
    if (s == null || !Platform.isAndroid || !_ready) return;
    try {
      await _fln.cancelAll();
      final now = DateTime.now();
      final list = s.events.where((e) {
        if (e.deleted || e.done) return false;
        final a = e.alarm;
        return a != null && a.isAfter(now);
      }).toList()
        ..sort((a, b) => a.alarm!.compareTo(b.alarm!));
      var id = 1;
      for (final e in list.take(300)) {
        final when = tz.TZDateTime.from(e.alarm!, tz.UTC);
        final title = e.title.isEmpty ? 'Без названия' : e.title;
        final body = e.isTask
            ? 'Задача · ${_hm(e.startDt)}'
            : (e.allDay ? 'Сегодня весь день' : 'Начало в ${_hm(e.startDt)}');
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            'events',
            'События и задачи',
            channelDescription: 'Напоминания календаря',
            importance: Importance.max,
            priority: Priority.high,
          ),
        );
        try {
          await _fln.zonedSchedule(
            id++,
            title,
            body,
            when,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (_) {
          try {
            await _fln.zonedSchedule(
              id++,
              title,
              body,
              when,
              details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  String _hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
}
