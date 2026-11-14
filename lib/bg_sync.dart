import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'applog.dart';
import 'backup.dart';
import 'phone_data.dart';
import 'store.dart';

const _kTask = 'asrbox_bg_sync';

/// Точка входа фоновой задачи WorkManager (отдельный изолят без интерфейса).
@pragma('vm:entry-point')
void bgDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final s = Store();
      await s.init();
      if (s.curId.isEmpty || !await s.unlockSilent()) return true; // ключей нет — тихо выходим
      if (!s.settings.bgSync) return true;
      if (!s.settings.syncConfigured && !s.settings.googleConfigured) return true;
      await s.syncAll();
      await Backup.autoIfDue(s);
      await PhoneData.autoIfDue(s);
      return true;
    } catch (e) {
      AppLog.I.e('bgsync', '$e');
      return true; // повторит по расписанию
    }
  });
}

class BgSync {
  static bool get available => Platform.isAndroid;
  static bool _inited = false;

  static Future<void> _init() async {
    if (_inited) return;
    await Workmanager().initialize(bgDispatcher);
    _inited = true;
  }

  /// Включить/выключить периодическую синхронизацию (Android сам выбирает момент,
  /// минимальный интервал — 15 минут).
  static Future<void> apply(bool on) async {
    if (!available) return;
    try {
      await _init();
      await Workmanager().cancelByUniqueName(_kTask);
      if (on) {
        await Workmanager().registerPeriodicTask(
          _kTask,
          _kTask,
          frequency: const Duration(minutes: 30),
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }
    } catch (e) {
      AppLog.I.e('bgsync', 'настройка: $e');
    }
  }
}
