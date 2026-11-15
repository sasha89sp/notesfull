import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'event_screen.dart';
import 'ics.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

class CalendarPage extends StatefulWidget {
  final Store store;
  const CalendarPage({super.key, required this.store});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // вид и выбранный день хранятся в Store: их же меняют мини-календарь и боковая панель
  String get _view => s.calView; // month | week | day | list | year
  set _view(String v) => s.setViewDay(s.viewDay, view: v);
  DateTime get _focus => s.viewDay;
  set _focus(DateTime d) => s.setViewDay(d);

  Store get s => widget.store;

  DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  // Индекс «день → события» строится один раз за перерисовку (а не на каждую ячейку).
  Map<int, List<CalEvent>> _idx = {};
  int _idxSig = -1;

  int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  Map<int, List<CalEvent>> _buildIndex() {
    final m = <int, List<CalEvent>>{};
    for (final e in s.events) {
      if (e.deleted) continue;
      final st = e.startDt;
      final en = e.isTask ? e.startDt : e.endDt;
      final sd = _d(st);
      final ed = e.allDay || e.isTask
          ? _d(en)
          : (en.isAfter(st) ? _d(en.subtract(const Duration(milliseconds: 1))) : sd);
      var d = sd;
      for (var i = 0; i < 400 && !d.isAfter(ed); i++) {
        m.putIfAbsent(_key(d), () => []).add(e);
        d = DateTime(d.year, d.month, d.day + 1);
      }
    }
    for (final l in m.values) {
      if (l.length > 1) l.sort((a, b) => a.start.compareTo(b.start));
    }
    return m;
  }

  List<CalEvent> _on(DateTime day) => _idx[_key(day)] ?? const <CalEvent>[];

  void _open(CalEvent e, {bool isNew = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EventScreen(store: s, event: e, isNew: isNew)));
    if (mounted) setState(() {});
  }

  void _create({bool task = false}) {
    final base = DateTime(
        _focus.year, _focus.month, _focus.day, DateTime.now().hour);
    _open(CalEvent.create(base, task: task), isNew: true);
  }

  void _shift(int dir) {
    setState(() {
      switch (_view) {
        case 'month':
          _focus = DateTime(_focus.year, _focus.month + dir, 1);
          break;
        case 'week':
          _focus = _focus.add(Duration(days: 7 * dir));
          break;
        case 'year':
          _focus = DateTime(_focus.year + dir, _focus.month, 1);
          break;
        default:
          _focus = _focus.add(Duration(days: dir));
      }
    });
  }

  String _title() {
    switch (_view) {
      case 'month':
        return '${kMonthsNom[_focus.month - 1]} ${_focus.year}';
      case 'week':
        final m = _monday(_focus);
        final e = m.add(const Duration(days: 6));
        return '${m.day} ${kMonths[m.month - 1]} — ${e.day} ${kMonths[e.month - 1]}';
      case 'day':
        return fmtDay(_focus);
      case 'year':
        return '${_focus.year}';
      default:
        return 'Предстоящие';
    }
  }

  DateTime _monday(DateTime d) =>
      _d(d).subtract(Duration(days: d.weekday - 1));

  Future<void> _exportIcs() async {
    final text = Ics.export(s.events);
    final ok = await saveBytes('calendar.ics', utf8.encode(text));
    if (ok && mounted) toast(context, 'Файл сохранён');
  }

  Future<void> _importIcs() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      withData: true,
    );
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final list = Ics.import(utf8.decode(r.files.first.bytes!, allowMalformed: true));
    s.events.addAll(list);
    s.eventsChanged();
    if (mounted) toast(context, 'Импортировано событий: ${list.length}');
  }

  Widget _tile(CalEvent e) {
    final time = e.allDay
        ? 'весь день'
        : e.isTask
            ? fmtTime(e.startDt)
            : '${fmtTime(e.startDt)}–${fmtTime(e.endDt)}';
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onTap: () => _open(e),
      child: Row(children: [
        if (e.isTask)
          Checkbox(
            value: e.done,
            onChanged: (v) {
              e.done = v ?? false;
              e.updatedAt = nowMs();
              s.eventsChanged();
              setState(() {});
            },
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.event, color: Theme.of(context).colorScheme.primary),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title.isEmpty ? 'Без названия' : e.title,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: e.done ? TextDecoration.lineThrough : null)),
            Text(time,
                style: TextStyle(color: Pal.secondary(context), fontSize: 13)),
          ]),
        ),
        if (e.remind >= 0)
          Icon(Icons.notifications_none, size: 16, color: Pal.secondary(context)),
      ]),
    );
  }

  Widget _dayList(DateTime day) {
    final list = _on(day);
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
            child: Text('Нет событий',
                style: TextStyle(color: Pal.secondary(context)))),
      );
    }
    return Column(children: [for (final e in list) _tile(e)]);
  }

  Widget _month() {
    final first = DateTime(_focus.year, _focus.month, 1);
    final start = _monday(first);
    final today = _d(DateTime.now());
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), children: [
      Row(children: [
        for (final w in kWeekdays)
          Expanded(
            child: Center(
              child: Text(w,
                  style: TextStyle(color: Pal.secondary(context), fontSize: 12)),
            ),
          ),
      ]),
      for (var w = 0; w < 6; w++)
        Row(children: [
          for (var i = 0; i < 7; i++)
            Builder(builder: (_) {
              final day = start.add(Duration(days: w * 7 + i));
              final inMonth = day.month == _focus.month;
              final sel = sameDay(day, _focus);
              final isToday = sameDay(day, today);
              final cnt = _on(day).length;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _focus = day),
                  child: Container(
                    height: 46,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: sel
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      border: isToday && !sel
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${day.day}',
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : (inMonth ? null : Pal.secondary(context)))),
                          if (cnt > 0)
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sel
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ]),
                  ),
                ),
              );
            }),
        ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Text(fmtDay(_focus),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      _dayList(_focus),
    ]);
  }

  Widget _week() {
    final m = _monday(_focus);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), children: [
      for (var i = 0; i < 7; i++) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
          child: Text('${kWeekdays[i]}, ${fmtDay(m.add(Duration(days: i)))}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sameDay(m.add(Duration(days: i)), DateTime.now())
                      ? Theme.of(context).colorScheme.primary
                      : Pal.secondary(context))),
        ),
        ..._on(m.add(Duration(days: i))).map(_tile),
      ],
    ]);
  }

  Widget _day() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [_dayList(_focus)],
      );

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        // индекс «день → события» пересобираем только когда события менялись
        var sig = s.events.length;
        for (final e in s.events) {
          sig = (sig * 31 + e.updatedAt + (e.deleted ? 7 : 0)) & 0x3fffffffffffffff;
        }
        if (sig != _idxSig) {
          _idx = _buildIndex();
          _idxSig = sig;
        }
        Widget body;
        switch (_view) {
          case 'week':
            body = _week();
            break;
          case 'day':
            body = _day();
            break;
          case 'list':
            body = _list();
            break;
          case 'year':
            body = _year();
            break;
          default:
            body = _month();
        }
        return Stack(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'month', label: Text('Месяц')),
                    ButtonSegment(value: 'week', label: Text('Неделя')),
                    ButtonSegment(value: 'day', label: Text('День')),
                    ButtonSegment(value: 'year', label: Text('Год')),
                    ButtonSegment(value: 'list', label: Text('Список')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (v) => setState(() => _view = v.first),
                ),
              ),
            ),
            Row(children: [
              if (_view != 'list') ...[
                IconButton(
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Center(
                    child: Text(_title(),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
                IconButton(
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right)),
              ] else
                const Spacer(),
              TextButton(
                  onPressed: () => setState(() => _focus = DateTime.now()),
                  child: const Text('Сегодня')),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'imp') _importIcs();
                  if (v == 'exp') _exportIcs();
                  if (v == 'sync') s.syncAll();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'imp', child: Text('Импорт .ics')),
                  PopupMenuItem(value: 'exp', child: Text('Экспорт .ics')),
                  PopupMenuItem(
                      value: 'sync', child: Text('Синхронизировать')),
                ],
              ),
            ]),
            Expanded(child: body),
          ]),
          Fab(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('Новое событие'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _create();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('Новая задача'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _create(task: true);
                    },
                  ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
