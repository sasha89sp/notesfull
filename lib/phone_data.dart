import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

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
}
