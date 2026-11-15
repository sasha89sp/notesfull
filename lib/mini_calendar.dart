import 'package:flutter/material.dart';
import 'calendars.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Мини-календарь месяца (7 колонок, ячейки 28 px, сегодня — индиго-кружок, точки у дней с событиями).
/// Общий день с расписанием и календарём: выбор меняет `Store.viewDay`.
class MiniCalendar extends StatefulWidget {
  final Store s;
  const MiniCalendar({super.key, required this.s});
  @override
  State<MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<MiniCalendar> {
  DateTime? _shown; // показанный месяц; null — следует за выбранным днём
  Set<int> _busy = {};
  int _sig = -1;

  Store get s => widget.s;

  int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Дни с событиями; пересчитываются только при изменении событий.
  void _refreshBusy() {
    var sig = s.events.length + Cals.sig(s.settings);
    for (final e in s.events) {
      sig = (sig * 31 + e.updatedAt + (e.deleted ? 7 : 0)) & 0x3fffffffffffffff;
    }
    if (sig == _sig) return;
    _sig = sig;
    final set = <int>{};
    for (final e in s.events) {
      if (e.deleted || !Cals.visible(s.settings, e)) continue;
      set.add(_key(e.startDt));
    }
    _busy = set;
  }

  @override
  Widget build(BuildContext context) {
    _refreshBusy();
    final cur = s.viewDay;
    final shown = _shown ?? DateTime(cur.year, cur.month, 1);
    final first = DateTime(shown.year, shown.month, 1);
    final lead = first.weekday - 1;
    final days = DateTime(shown.year, shown.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final today = DateTime.now();
    final acc = Pal.accent(context);
    Widget cell(int i) {
      final n = i - lead + 1;
      if (n < 1 || n > days) return const SizedBox(width: 28, height: 28);
      final d = DateTime(shown.year, shown.month, n);
      final isToday = sameDay(d, today);
      final sel = sameDay(d, cur);
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          setState(() => _shown = null);
          s.setViewDay(d);
        },
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday ? acc : (sel ? acc.withOpacity(0.14) : null),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday || sel ? FontWeight.w600 : FontWeight.w400,
                    color: isToday ? Colors.white : null)),
            if (_busy.contains(_key(d)) && !isToday)
              Positioned(
                  bottom: 3,
                  child: Container(width: 3, height: 3, decoration: BoxDecoration(color: acc, shape: BoxShape.circle))),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Text('${kMonthsNom[shown.month - 1]} ${shown.year}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          InkWell(
              onTap: () => setState(() => _shown = DateTime(shown.year, shown.month - 1, 1)),
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_left, size: 18))),
          InkWell(
              onTap: () => setState(() => _shown = DateTime(shown.year, shown.month + 1, 1)),
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_right, size: 18))),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final w in kWeekdays)
            SizedBox(
                width: 28,
                child: Text(w, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: Pal.muted(context)))),
        ]),
        for (var r = 0; r < rows; r++)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (var c = 0; c < 7; c++) cell(r * 7 + c)]),
      ]),
    );
  }
}
