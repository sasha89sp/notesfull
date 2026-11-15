import 'dart:convert';
import 'package:http/http.dart' as http;
import 'applog.dart';
import 'calendars.dart';
import 'ics.dart';
import 'models.dart';
import 'store.dart';

/// Подписка на онлайн-календарь по ссылке iCal (.ics / webcal://), только чтение.
/// События получают стабильные id, поэтому обновление не плодит дубли, а исчезнувшие
/// из ленты события помечаются удалёнными. Повторяющиеся события (RRULE) показываются
/// только первым вхождением.
class IcalSub {
  static bool _busy = false;

  static String _url(String u) => u.trim().replaceFirst(RegExp(r'^webcal://', caseSensitive: false), 'https://');

  /// Обновить один календарь. Возвращает «добавлено/обновлено/удалено».
  static Future<String> refresh(Store s, CalDef c) async {
    final r = await http.get(Uri.parse(_url(c.url))).timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) throw 'Сервер ответил ${r.statusCode}';
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (!text.contains('BEGIN:VCALENDAR')) throw 'По ссылке не календарь iCal';
    final seen = <String>{};
    var added = 0, upd = 0;
    for (final m in IcsRaw.parse(text)) {
      final e = IcsRaw.toCal(m, calId: c.id);
      if (e == null) continue;
      // id включает календарь: одно и то же событие из двух лент не склеивается
      e.id = 'sub${c.id.hashCode.toUnsigned(24).toRadixString(36)}_${e.id}';
      seen.add(e.id);
      final i = s.events.indexWhere((x) => x.id == e.id);
      if (i < 0) {
        s.events.add(e);
        added++;
      } else {
        final o = s.events[i];
        if (o.title != e.title || o.start != e.start || o.end != e.end || o.notes != e.notes || o.allDay != e.allDay || o.deleted) {
          o
            ..title = e.title
            ..notes = e.notes
            ..start = e.start
            ..end = e.end
            ..allDay = e.allDay
            ..deleted = false
            ..updatedAt = nowMs();
          upd++;
        }
      }
    }
    var del = 0;
    for (final e in s.events) {
      if (e.calId == c.id && !e.deleted && !seen.contains(e.id)) {
        e.deleted = true;
        e.updatedAt = nowMs();
        del++;
      }
    }
    if (added + upd + del > 0) s.eventsChanged();
    return 'добавлено $added, обновлено $upd, удалено $del';
  }

  /// По расписанию (из синхронизации): календари, у которых прошёл интервал.
  static Future<void> syncDue(Store s, {bool force = false}) async {
    if (_busy) return;
    final l = Cals.all(s.settings);
    final subs = l.where((c) => c.type == 'url' && c.url.isNotEmpty).toList();
    if (subs.isEmpty) return;
    _busy = true;
    var changed = false;
    try {
      for (final c in subs) {
        if (!force && nowMs() - c.last < 120 * 60000) continue;
        try {
          final res = await refresh(s, c);
          AppLog.I.i('ical', '«${c.name}»: $res');
        } catch (e) {
          AppLog.I.e('ical', '«${c.name}»: $e');
        }
        c.last = nowMs();
        changed = true;
      }
      if (changed) {
        Cals.save(s.settings, l);
        await s.saveSettings(touch: false);
      }
    } finally {
      _busy = false;
    }
  }
}
