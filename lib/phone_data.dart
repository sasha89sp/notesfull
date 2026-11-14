import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'applog.dart';
import 'backup.dart';
import 'crypto.dart';
import 'models.dart';
import 'store.dart';

/// Данные телефона (Android): журнал звонков, контакты, SMS, сети Wi-Fi.
/// Нативная часть — BackupBridge.kt (ci/patch_backup.py).
class PhoneData {
  static const MethodChannel _ch = MethodChannel('asrbox/backup');

  static bool get available => Platform.isAndroid;

  static Future<bool> hasPerms(String group) async =>
      (await _ch.invokeMethod<bool>('hasPerms', group)) ?? false;

  static Future<bool> requestPerms(String group) async =>
      (await _ch.invokeMethod<bool>('requestPerms', group)) ?? false;

  static Future<List<dynamic>> _list(String m) async {
    final s = await _ch.invokeMethod<String>(m) ?? '[]';
    return jsonDecode(s) as List<dynamic>;
  }

  static Future<int> _put(String m, List<dynamic> items) async =>
      (await _ch.invokeMethod<int>(m, jsonEncode(items))) ?? 0;

  static Future<List<dynamic>> exportCalls() => _list('exportCalls');
  static Future<int> importCalls(List<dynamic> l) => _put('importCalls', l);
  static Future<List<dynamic>> exportContacts() => _list('exportContacts');
  static Future<int> importContacts(List<dynamic> l) => _put('importContacts', l);
  static Future<List<dynamic>> exportSms() => _list('exportSms');

  /// -1 — приложение не является SMS-приложением по умолчанию, запись запрещена Android.
  static Future<int> importSms(List<dynamic> l) => _put('importSms', l);
  static Future<List<dynamic>> exportWifi() => _list('exportWifi');
  static Future<int> importWifi(List<dynamic> l) => _put('importWifi', l);

  // ----------------------------------------------------------- vCard

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\;');

  static String _unesc(String s) => s
      .replaceAll('\\n', '\n')
      .replaceAll('\\N', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\;', ';')
      .replaceAll('\\\\', '\\');

  static String toVcf(List<dynamic> contacts) {
    final b = StringBuffer();
    for (final c in contacts) {
      final m = c as Map;
      b.write('BEGIN:VCARD\r\nVERSION:3.0\r\n');
      final name = (m['name'] ?? '').toString();
      b.write('FN:${_esc(name)}\r\nN:${_esc(name)};;;;\r\n');
      for (final p in (m['phones'] as List? ?? [])) {
        b.write('TEL;TYPE=CELL:${_esc(p.toString())}\r\n');
      }
      for (final e in (m['emails'] as List? ?? [])) {
        b.write('EMAIL:${_esc(e.toString())}\r\n');
      }
      final org = (m['org'] ?? '').toString();
      if (org.isNotEmpty) b.write('ORG:${_esc(org)}\r\n');
      final note = (m['note'] ?? '').toString();
      if (note.isNotEmpty) b.write('NOTE:${_esc(note)}\r\n');
      b.write('END:VCARD\r\n');
    }
    return b.toString();
  }

  static List<Map<String, dynamic>> parseVcf(String text) {
    // разворачиваем «сложенные» строки (продолжение начинается с пробела)
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\n ', '').replaceAll('\n\t', '').split('\n');
    final out = <Map<String, dynamic>>[];
    Map<String, dynamic>? cur;
    for (final raw in lines) {
      final l = raw.trimRight();
      final u = l.toUpperCase();
      if (u == 'BEGIN:VCARD') {
        cur = {'name': '', 'phones': <String>[], 'emails': <String>[], 'org': '', 'note': ''};
        continue;
      }
      if (u == 'END:VCARD') {
        if (cur != null && ((cur['name'] as String).isNotEmpty || (cur['phones'] as List).isNotEmpty)) {
          out.add(cur);
        }
        cur = null;
        continue;
      }
      if (cur == null) continue;
      final i = l.indexOf(':');
      if (i < 0) continue;
      final key = l.substring(0, i).split(';').first.toUpperCase();
      final val = _unesc(l.substring(i + 1));
      switch (key) {
        case 'FN':
          cur['name'] = val;
        case 'N':
          if ((cur['name'] as String).isEmpty) {
            final p = l.substring(i + 1).split(';');
            cur['name'] = [if (p.length > 1) p[1], p[0]].where((x) => x.isNotEmpty).join(' ');
          }
        case 'TEL':
          (cur['phones'] as List).add(val);
        case 'EMAIL':
          (cur['emails'] as List).add(val);
        case 'ORG':
          cur['org'] = val.replaceAll(';', ' ').trim();
        case 'NOTE':
          cur['note'] = val;
      }
    }
    return out;
  }

  static String callTypeName(int t) {
    switch (t) {
      case 1:
        return 'входящий';
      case 2:
        return 'исходящий';
      case 3:
        return 'пропущенный';
      case 5:
        return 'отклонённый';
      default:
        return 'тип $t';
    }
  }

  // ----------------------------------------------------------- бэкап телефона одной кнопкой

  static bool _busy = false;

  static String _stamp() {
    final d = DateTime.now();
    String x(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${x(d.month)}${x(d.day)}_${x(d.hour)}${x(d.minute)}${x(d.second)}';
  }

  /// Собирает всё, что доступно с телефона (звонки, контакты, SMS, Wi-Fi), в один архив.
  /// [ask] — запрашивать недостающие разрешения (в фоне по расписанию — нет).
  /// Возвращает (архив, подпись). Категории без разрешения пропускаются.
  static Future<(List<int>, String)> collect(Store s, {required bool ask}) async {
    final ar = Archive();
    final done = <String>[];
    final skipped = <String>[];
    void add(String name, List<int> b) => ar.addFile(ArchiveFile(name, b.length, b));

    Future<bool> ok(String g) async =>
        await hasPerms(g) || (ask && await requestPerms(g));

    if (await ok('calls')) {
      final l = await exportCalls();
      add('calls.json', utf8.encode(jsonEncode(l)));
      done.add('звонки ${l.length}');
    } else {
      skipped.add('звонки');
    }
    if (await ok('contacts')) {
      final l = await exportContacts();
      add('contacts.json', utf8.encode(jsonEncode(l)));
      add('contacts.vcf', utf8.encode(toVcf(l)));
      done.add('контакты ${l.length}');
    } else {
      skipped.add('контакты');
    }
    if (await ok('sms')) {
      final l = await exportSms();
      add('sms.json', utf8.encode(jsonEncode(l)));
      done.add('SMS ${l.length}');
    } else {
      skipped.add('SMS');
    }
    if (await ok('wifi')) {
      final l = await exportWifi();
      add('wifi.json', utf8.encode(jsonEncode(l)));
      done.add('Wi-Fi ${l.length}');
    } else {
      skipped.add('Wi-Fi');
    }
    if (done.isEmpty) throw 'Нет ни одного разрешения для чтения данных телефона';
    add('manifest.json', utf8.encode(jsonEncode({'created': DateTime.now().toIso8601String(), 'items': done})));
    final bytes = ZipEncoder().encode(ar);
    if (bytes == null) throw 'Не удалось собрать архив';
    return (bytes, '${done.join(', ')}${skipped.isEmpty ? '' : '. Пропущено (нет разрешения): ${skipped.join(', ')}'}');
  }

  /// Одна кнопка «+»: собрать всё и сразу загрузить в облако (если оно настроено).
  /// Файл шифруется ключом профиля. Если облако не настроено — вернёт байты для сохранения.
  static Future<({String name, List<int> bytes, String info, bool uploaded})> runAll(Store s,
      {required bool ask, bool upload = true}) async {
    if (_busy) throw 'Бэкап телефона уже выполняется';
    _busy = true;
    try {
      final (zip, info) = await collect(s, ask: ask);
      var bytes = zip;
      var name = 'asrbox_phone_${_stamp()}.zip';
      if (s.syncKey != null) {
        bytes = await Crypto.encrypt(s.syncKey!, zip);
        name = '$name.enc';
      }
      var up = false;
      if (upload && Backup.canUpload(s.settings)) {
        await Backup.uploadPhone(s, name, bytes);
        up = true;
      }
      s.settings.bkPhoneLast = nowMs();
      await s.saveSettings(touch: false);
      AppLog.I.i('backup', 'Бэкап телефона: $info${up ? ' (загружен)' : ''}');
      return (name: name, bytes: bytes, info: info, uploaded: up);
    } finally {
      _busy = false;
    }
  }

  /// По расписанию (пока приложение открыто): без запроса разрешений.
  static Future<void> autoIfDue(Store s) async {
    final st = s.settings;
    if (!available || st.bkPhoneEvery <= 0 || s.key == null || !Backup.canUpload(st)) return;
    if (nowMs() - st.bkPhoneLast < Duration(hours: st.bkPhoneEvery).inMilliseconds) return;
    try {
      await runAll(s, ask: false);
    } catch (e) {
      AppLog.I.e('backup', 'Автобэкап телефона не удался: $e');
    }
  }
}
