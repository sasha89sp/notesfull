// ▸ Часть calendar_page.dart: десктопный вид календаря в стиле Noteplan (шапка с видами, большая сетка месяца, недельные колонки)
part of 'calendar_page.dart';

extension _ExtCalendarDesktop on _CalendarPageState {
  static const _views = [
    ('day', 'День', Icons.today_outlined),
    ('week', 'Неделя', Icons.view_week_outlined),
    ('month', 'Месяц', Icons.calendar_view_month_outlined),
    ('year', 'Год', Icons.calendar_today_outlined),
    ('list', 'Список', Icons.list_alt_outlined),
  ];

  Widget _deskHeader() {
    final acc = Pal.accent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
      child: Row(children: [
        Expanded(
          child: Text(_view == 'list' ? 'Предстоящие' : _title(),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),
        for (final v in _views)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: _view == v.$1 ? acc : Pal.secondary(context),
                backgroundColor: _view == v.$1 ? acc.withOpacity(0.12) : null,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () => setState(() => _view = v.$1),
              icon: Icon(v.$3, size: 17),
              label: Text(v.$2, style: const TextStyle(fontSize: 13)),
            ),
          ),
        const SizedBox(width: 10),
        if (_view != 'list') ...[
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          OutlinedButton(onPressed: () => setState(() => _focus = DateTime.now()), child: const Text('Сегодня')),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ],
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          onPressed: _create,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Событие'),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'task') _create(task: true);
            if (v == 'imp') _importIcs();
            if (v == 'exp') _exportIcs();
            if (v == 'sync') s.syncAll(scope: 'calendar');
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'task', child: Text('Новая задача')),
            PopupMenuItem(value: 'imp', child: Text('Импорт .ics')),
            PopupMenuItem(value: 'exp', child: Text('Экспорт .ics')),
            PopupMenuItem(value: 'sync', child: Text('Синхронизировать')),
          ],
        ),
      ]),
    );
  }

  Widget _chip(CalEvent e) {
    final c = Cals.color(s.settings, e);
    return GestureDetector(
      onTap: () => _open(e),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(4)),
        child: Text(e.title.isEmpty ? 'Без названия' : e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5,
                color: c,
                fontWeight: FontWeight.w500,
                decoration: e.done ? TextDecoration.lineThrough : null)),
      ),
    );
  }

  /// Большая сетка месяца: клетки растягиваются на всё окно, внутри — цветные плашки событий.
  Widget _deskMonth() {
    final first = DateTime(_focus.year, _focus.month, 1);
    final start = _monday(first);
    final today = _d(DateTime.now());
    final acc = Pal.accent(context);
    final line = Pal.border(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(children: [
        Row(children: [
          for (final w in kWeekdays)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Pal.secondary(context), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: line), left: BorderSide(color: line))),
            child: Column(children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Row(children: [
                    for (var i = 0; i < 7; i++)
                      Builder(builder: (_) {
                        final day = start.add(Duration(days: w * 7 + i));
                        final inMonth = day.month == _focus.month;
                        final sel = sameDay(day, _focus);
                        final isToday = sameDay(day, today);
                        final list = _on(day);
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _focus = day),
                            onDoubleTap: () {
                              setState(() => _focus = day);
                              _create();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: sel ? acc.withOpacity(0.08) : null,
                                border: Border(right: BorderSide(color: line), bottom: BorderSide(color: line)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: isToday ? acc : null, shape: BoxShape.circle),
                                  child: Text('${day.day}',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                                          color: isToday
                                              ? Colors.white
                                              : (inMonth ? null : Pal.secondary(context).withOpacity(0.6)))),
                                ),
                                const SizedBox(height: 2),
                                Expanded(
                                  child: ClipRect(
                                    child: SingleChildScrollView(
                                      physics: const NeverScrollableScrollPhysics(),
                                      child: Column(children: [
                                        for (final e in list.take(3)) _chip(e),
                                        if (list.length > 3)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('ещё ${list.length - 3}',
                                                style: TextStyle(fontSize: 11, color: Pal.secondary(context))),
                                          ),
                                      ]),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        );
                      }),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Неделя: семь колонок с датами и событиями.
  Widget _deskWeek() {
    final m = _monday(_focus);
    final acc = Pal.accent(context);
    final line = Pal.border(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (_) {
              final day = m.add(Duration(days: i));
              final isToday = sameDay(day, DateTime.now());
              return Container(
                decoration: BoxDecoration(border: Border(left: BorderSide(color: line), top: BorderSide(color: line), bottom: BorderSide(color: line), right: i == 6 ? BorderSide(color: line) : BorderSide.none)),
                padding: const EdgeInsets.all(6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GestureDetector(
                    onTap: () => setState(() => _focus = day),
                    child: Text('${kWeekdays[i]} ${day.day}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isToday ? acc : Pal.secondary(context))),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(children: [
                      for (final e in _on(day))
                        _chip(e),
                    ]),
                  ),
                ]),
              );
            }),
          ),
      ]),
    );
  }
}
