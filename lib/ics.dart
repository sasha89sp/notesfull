import 'dart:convert';
import 'models.dart';

class Ics {
  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');

  static String _unesc(String s) => s
      .replaceAll('\\n', '\n')
      .replaceAll('\\N', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  static String _day(DateTime d) => '${d.year}${two(d.month)}${two(d.day)}';

  static String export(List<CalEvent> list) {
    final sb = StringBuffer();
    sb.write('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//ASRbox//RU\r\n');
    for (final e in list.where((x) => !x.deleted && !x.isTask)) {
      sb.write('BEGIN:VEVENT\r\nUID:${e.id}@mysecure\r\n');
      sb.write('DTSTAMP:${_utc(DateTime.now())}\r\n');
      if (e.allDay) {
        sb.write('DTSTART;VALUE=DATE:${_day(e.startDt)}\r\n');
        sb.write(
            'DTEND;VALUE=DATE:${_day(e.endDt.add(const Duration(days: 1)))}\r\n');
      } else {
        sb.write('DTSTART:${_utc(e.startDt)}\r\nDTEND:${_utc(e.endDt)}\r\n');
      }
      sb.write('SUMMARY:${_esc(e.title)}\r\n');
      if (e.notes.isNotEmpty) sb.write('DESCRIPTION:${_esc(e.notes)}\r\n');
      sb.write('END:VEVENT\r\n');
    }
    sb.write('END:VCALENDAR\r\n');
    return sb.toString();
  }

  static DateTime? _parseDt(String v, bool dateOnly) {
    final s = v.trim();
    if (s.length < 8) return null;
    final y = int.tryParse(s.substring(0, 4));
    final mo = int.tryParse(s.substring(4, 6));
    final d = int.tryParse(s.substring(6, 8));
    if (y == null || mo == null || d == null) return null;
    if (dateOnly || s.length < 15) return DateTime(y, mo, d);
    final h = int.tryParse(s.substring(9, 11)) ?? 0;
    final mi = int.tryParse(s.substring(11, 13)) ?? 0;
    final se = int.tryParse(s.substring(13, 15)) ?? 0;
    if (s.endsWith('Z')) return DateTime.utc(y, mo, d, h, mi, se).toLocal();
    return DateTime(y, mo, d, h, mi, se);
  }

  static List<CalEvent> import(String text) {
    // разворачиваем сложенные строки
    final lines = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += raw.substring(1);
      } else {
        lines.add(raw);
      }
    }
    final out = <CalEvent>[];
    Map<String, String>? cur;
    for (final l in lines) {
      if (l == 'BEGIN:VEVENT') {
        cur = {};
      } else if (l == 'END:VEVENT' && cur != null) {
        final dateOnly = (cur['DTSTART_P'] ?? '').contains('VALUE=DATE') &&
            !(cur['DTSTART_P'] ?? '').contains('DATE-TIME');
        final s = _parseDt(cur['DTSTART'] ?? '', dateOnly);
        if (s != null) {
          var e = _parseDt(cur['DTEND'] ?? '', dateOnly) ??
              s.add(const Duration(hours: 1));
          if (dateOnly) {
            e = e.subtract(const Duration(days: 1));
            if (e.isBefore(s)) e = s;
          }
          out.add(CalEvent(
            id: newId(),
            title: _unesc(cur['SUMMARY'] ?? ''),
            notes: _unesc(cur['DESCRIPTION'] ?? ''),
            start: s.millisecondsSinceEpoch,
            end: e.millisecondsSinceEpoch,
            allDay: dateOnly,
            remind: dateOnly ? -1 : 15,
            updatedAt: nowMs(),
          ));
        }
        cur = null;
      } else if (cur != null) {
        final i = l.indexOf(':');
        if (i < 0) continue;
        final head = l.substring(0, i);
        final name = head.split(';').first.toUpperCase();
        cur[name] = l.substring(i + 1);
        if (head.contains(';')) cur['${name}_P'] = head;
      }
    }
    return out;
  }
}
