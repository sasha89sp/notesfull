// ▸ Часть ics.dart: Импорт и экспорт календаря .ics  [содержит: IcsRaw]
part of 'ics.dart';


/// «Сырые» события VEVENT: список «свойство → значение», где ключ — имя вместе с параметрами
/// (например `DTSTART;VALUE=DATE`). Нужны блоку «Календарь .ics» в заметке: все свойства
/// сохраняются и редактируются, неизвестные не теряются.
class IcsRaw {
  static List<String> _unfold(String text) {
    final lines = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += raw.substring(1);
      } else {
        lines.add(raw);
      }
    }
    return lines;
  }

  static List<Map<String, String>> parse(String text) {
    final out = <Map<String, String>>[];
    Map<String, String>? cur;
    var depth = 0; // вложенные компоненты (VALARM) сохраняются как есть в ключе '#nested'
    for (final l in _unfold(text)) {
      if (l == 'BEGIN:VEVENT') {
        cur = {};
        depth = 0;
      } else if (l == 'END:VEVENT' && cur != null) {
        out.add(cur);
        cur = null;
      } else if (cur != null) {
        if (l.startsWith('BEGIN:')) {
          depth++;
          cur['#nested'] = '${cur['#nested'] ?? ''}$l\n';
        } else if (l.startsWith('END:')) {
          if (depth > 0) depth--;
          cur['#nested'] = '${cur['#nested'] ?? ''}$l\n';
        } else if (depth == 0) {
          final i = l.indexOf(':');
          if (i > 0) cur[l.substring(0, i)] = l.substring(i + 1);
        } else {
          cur['#nested'] = '${cur['#nested'] ?? ''}$l\n';
        }
      }
    }
    return out;
  }

  static String build(List<Map<String, String>> evs) {
    final sb = StringBuffer('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//ASRbox//RU\r\n');
    for (final m in evs) {
      sb.write('BEGIN:VEVENT\r\n');
      for (final k in m.keys.toList()) {
        if (k == '#nested') continue;
        sb.write('$k:${m[k]}\r\n');
      }
      final nested = m['#nested'];
      if (nested != null && nested.isNotEmpty) {
        for (final l in nested.split('\n').where((x) => x.isNotEmpty)) {
          sb.write('$l\r\n');
        }
      }
      sb.write('END:VEVENT\r\n');
    }
    sb.write('END:VCALENDAR\r\n');
    return sb.toString();
  }

  static String name(String key) => key.split(';').first.toUpperCase();

  static String? get(Map<String, String> m, String n) {
    for (final e in m.entries) {
      if (name(e.key) == n) return e.value;
    }
    return null;
  }

  static String? keyOf(Map<String, String> m, String n) {
    for (final k in m.keys) {
      if (name(k) == n) return k;
    }
    return null;
  }

  static String text(String v) => Ics._unesc(v);
  static String esc(String v) => Ics._esc(v);

  static bool isAllDay(Map<String, String> m) {
    final k = keyOf(m, 'DTSTART') ?? '';
    return k.contains('VALUE=DATE') && !k.contains('DATE-TIME');
  }

  static DateTime? start(Map<String, String> m) {
    final v = get(m, 'DTSTART');
    return v == null ? null : Ics._parseDt(v, isAllDay(m));
  }

  static DateTime? end(Map<String, String> m) {
    final v = get(m, 'DTEND');
    if (v == null) return null;
    final e = Ics._parseDt(v, isAllDay(m));
    return e != null && isAllDay(m) ? e.subtract(const Duration(days: 1)) : e;
  }

  /// Записать дату начала/конца (конец весь день — включительно, в файл пишется +1 день).
  static void setDate(Map<String, String> m, String prop, DateTime d, bool allDay) {
    final old = keyOf(m, prop);
    if (old != null) m.remove(old);
    if (allDay) {
      final x = prop == 'DTEND' ? d.add(const Duration(days: 1)) : d;
      m['$prop;VALUE=DATE'] = Ics._day(x);
    } else {
      m[prop] = Ics._utc(d);
    }
  }

  /// Раскрытие повторов (RRULE: DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, BYDAY, EXDATE)
  /// в начала вхождений внутри [from, to]. Без RRULE возвращает единственное начало (если попадает в окно).
  static List<DateTime> occurrences(Map<String, String> m, DateTime from, DateTime to) {
    final s = start(m);
    if (s == null) return const [];
    final rule = get(m, 'RRULE');
    if (rule == null || rule.isEmpty) return [if (!s.isAfter(to)) s];
    final p = <String, String>{};
    for (final part in rule.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) p[part.substring(0, i).toUpperCase()] = part.substring(i + 1);
    }
    final freq = p['FREQ'] ?? '';
    final interval = math.max(1, int.tryParse(p['INTERVAL'] ?? '') ?? 1);
    final count = int.tryParse(p['COUNT'] ?? '');
    DateTime? until;
    if (p['UNTIL'] != null) until = Ics._parseDt(p['UNTIL']!, p['UNTIL']!.length <= 8);
    final ex = <String>{};
    for (final e in m.entries.where((e) => name(e.key) == 'EXDATE')) {
      for (final v in e.value.split(',')) {
        final d = Ics._parseDt(v, v.length <= 8);
        if (d != null) ex.add('${d.year}-${d.month}-${d.day}');
      }
    }
    const wd = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};
    final days = <int>[
      for (final x in (p['BYDAY'] ?? '').split(','))
        if (wd[x.replaceAll(RegExp(r'[^A-Z]'), '')] != null) wd[x.replaceAll(RegExp(r'[^A-Z]'), '')]!,
    ]..sort();
    if (days.isEmpty) days.add(s.weekday);

    DateTime at(int y, int mo, int d) => DateTime(y, mo, d, s.hour, s.minute, s.second);
    final out = <DateTime>[];
    var n = 0; // номер вхождения (для COUNT)
    bool take(DateTime d) {
      if (d.isBefore(s)) return true;
      if (until != null && d.isAfter(until)) return false;
      n++;
      if (count != null && n > count) return false;
      if (d.isAfter(to)) return false;
      if (!d.isBefore(from) && !ex.contains('${d.year}-${d.month}-${d.day}')) out.add(d);
      return true;
    }

    for (var k = 0; k < 4000; k++) {
      switch (freq) {
        case 'DAILY':
          if (!take(at(s.year, s.month, s.day + k * interval))) return out;
          break;
        case 'WEEKLY':
          final monday = DateTime(s.year, s.month, s.day - (s.weekday - 1) + 7 * interval * k);
          for (final d in days) {
            if (!take(at(monday.year, monday.month, monday.day + d - 1))) return out;
          }
          break;
        case 'MONTHLY':
          final mo = DateTime(s.year, s.month + k * interval, 1);
          final last = DateTime(mo.year, mo.month + 1, 0).day;
          if (s.day <= last && !take(at(mo.year, mo.month, s.day))) return out;
          if (mo.year > to.year + 1) return out;
          break;
        case 'YEARLY':
          if (!take(at(s.year + k * interval, s.month, s.day))) return out;
          break;
        default:
          return out;
      }
      if (k > 1 && out.isNotEmpty && out.last.isAfter(to)) return out;
    }
    return out;
  }

  static CalEvent? toCal(Map<String, String> m, {String calId = ''}) {
    final s = start(m);
    if (s == null) return null;
    final allDay = isAllDay(m);
    var e = end(m) ?? (allDay ? s : s.add(const Duration(hours: 1)));
    if (e.isBefore(s)) e = s;
    final uid = get(m, 'UID') ?? '${s.millisecondsSinceEpoch}${get(m, 'SUMMARY') ?? ''}';
    final loc = get(m, 'LOCATION');
    final desc = text(get(m, 'DESCRIPTION') ?? '');
    return CalEvent(
      id: 'ics${uid.hashCode.toUnsigned(32).toRadixString(36)}',
      title: text(get(m, 'SUMMARY') ?? ''),
      notes: loc == null || loc.isEmpty ? desc : '${text(loc)}${desc.isEmpty ? '' : '\n$desc'}',
      start: s.millisecondsSinceEpoch,
      end: e.millisecondsSinceEpoch,
      allDay: allDay,
      remind: allDay ? -1 : 15,
      calId: calId,
      updatedAt: nowMs(),
    );
  }
}