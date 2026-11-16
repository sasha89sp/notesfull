// ▸ Часть calendar_page.dart: Экран календаря (месяц/список событий и задач)  [содержит: _ExtCalendarPageState2]
part of 'calendar_page.dart';

extension _ExtCalendarPageState2 on _CalendarPageState {

  /// Год: 12 мини-месяцев; день с событиями выделен, нажатие открывает месяц.
  Widget _year() {
    final today = _d(DateTime.now());
    final acc = Pal.accent(context);
    Widget month(int m) {
      final first = DateTime(_focus.year, m, 1);
      final lead = first.weekday - 1;
      final days = DateTime(_focus.year, m + 1, 0).day;
      final cells = <Widget>[];
      for (var i = 0; i < 42; i++) {
        final n = i - lead + 1;
        if (n < 1 || n > days) {
          cells.add(const SizedBox.shrink());
          continue;
        }
        final day = DateTime(_focus.year, m, n);
        final isToday = sameDay(day, today);
        final has = _on(day).isNotEmpty;
        cells.add(InkWell(
          onTap: () => s.setViewDay(day, view: 'day'),
          child: Container(
            margin: const EdgeInsets.all(1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: isToday ? acc : null, shape: BoxShape.circle),
            child: Text('$n',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: has ? FontWeight.w700 : FontWeight.w400,
                    color: isToday
                        ? Colors.white
                        : has
                            ? acc
                            : Pal.secondary(context))),
          ),
        ));
      }
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => s.setViewDay(DateTime(_focus.year, m, 1), view: 'month'),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(kMonthsNom[m - 1],
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(child: GridView.count(crossAxisCount: 7, physics: const NeverScrollableScrollPhysics(), children: cells)),
        ]),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 560 ? 3 : 2;
      return GridView.count(
        crossAxisCount: cols,
        childAspectRatio: 1.05,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
        children: [for (var m = 1; m <= 12; m++) month(m)],
      );
    });
  }

  Widget _list() {
    final today = _d(DateTime.now());
    final out = <Widget>[];
    for (var i = 0; i < 120; i++) {
      final day = today.add(Duration(days: i));
      final list = _on(day);
      if (list.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
        child: Text(fmtDay(day),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Pal.secondary(context))),
      ));
      out.addAll(list.map(_tile));
    }
    if (out.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
            child: Text('Предстоящих событий нет',
                style: TextStyle(color: Pal.secondary(context)))),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), children: out);
  }
}
