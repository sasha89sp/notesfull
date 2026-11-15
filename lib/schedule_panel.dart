import 'package:flutter/material.dart';
import 'event_screen.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Правая панель «Расписание»: вертикальный таймлайн выбранного дня
/// (метки времени, карточки событий по длительности, текущее время).
class SchedulePanel extends StatefulWidget {
  final Store store;
  const SchedulePanel({super.key, required this.store});
  @override
  State<SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<SchedulePanel> {
  static const double hour = 60; // высота часа
  late final ScrollController _sc;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now().hour;
    _sc = ScrollController(initialScrollOffset: ((h - 1).clamp(0, 16)) * hour);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  List<CalEvent> _eventsOf(DateTime day) {
    final a = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final b = a + const Duration(days: 1).inMilliseconds;
    final out = <CalEvent>[];
    for (final e in s.events) {
      if (e.deleted) continue;
      if (e.isTask) {
        if (e.start >= a && e.start < b) out.add(e);
      } else if (e.start < b && (e.end > a || e.start >= a)) {
        out.add(e);
      }
    }
    out.sort((x, y) => x.start.compareTo(y.start));
    return out;
  }

  void _open(CalEvent e, {bool isNew = false}) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => EventScreen(store: s, event: e, isNew: isNew)));

  void _add() {
    final d = s.viewDay;
    _open(CalEvent.create(DateTime(d.year, d.month, d.day, DateTime.now().hour)), isNew: true);
  }

  /// Раскладка пересекающихся событий по «дорожкам».
  Map<CalEvent, (int, int)> _lanes(List<CalEvent> list, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    int top(CalEvent e) => ((e.start - dayStart) / 60000).clamp(0, 1439).round();
    int len(CalEvent e) => e.isTask ? 48 : ((e.end - e.start) / 60000).round().clamp(48, 1440).toInt();
    final res = <CalEvent, (int, int)>{};
    var group = <CalEvent>[];
    var groupEnd = -1;
    final laneEnds = <int>[];
    void flush() {
      final n = laneEnds.length;
      for (final e in group) {
        res[e] = (res[e]!.$1, n);
      }
      group = [];
      laneEnds.clear();
      groupEnd = -1;
    }

    for (final e in list) {
      final st = top(e);
      if (group.isNotEmpty && st >= groupEnd) flush();
      var lane = laneEnds.indexWhere((end) => end <= st);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(0);
      }
      laneEnds[lane] = st + len(e);
      groupEnd = groupEnd < st + len(e) ? st + len(e) : groupEnd;
      group.add(e);
      res[e] = (lane, 1);
    }
    flush();
    return res;
  }

  Widget _timeline(DateTime day) {
    final list = _eventsOf(day).where((e) => !e.allDay).toList();
    final lanes = _lanes(list, day);
    final dayStart = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final now = DateTime.now();
    final isToday = sameDay(day, now);
    return LayoutBuilder(builder: (context, box) {
      const left = 50.0, right = 10.0;
      final w = box.maxWidth - left - right;
      return SizedBox(
        height: 24 * hour + 10,
        child: Stack(children: [
          for (var h = 0; h < 24; h++) ...[
            Positioned(
              left: 0,
              top: h * hour - 6,
              width: left - 8,
              child: Text('${two(h)}:00',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Pal.muted(context))),
            ),
            Positioned(left: left, right: 0, top: h * hour, child: Divider(height: 1, color: Pal.border(context))),
          ],
          for (final e in list)
            () {
              final (lane, n) = lanes[e]!;
              final top = ((e.start - dayStart) / 60000).clamp(0, 1439).toDouble();
              final h = e.isTask ? 48.0 : ((e.end - e.start) / 60000).clamp(48, 1440).toDouble();
              final cw = w / n;
              return Positioned(
                left: left + lane * cw,
                width: cw - 3,
                top: top,
                height: h - 2,
                child: _EventCard(event: e, store: s, onOpen: () => _open(e)),
              );
            }(),
          if (isToday)
            Positioned(
              left: left - 4,
              right: 0,
              top: now.hour * hour + now.minute,
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: Pal.error(context), shape: BoxShape.circle)),
                Expanded(child: Container(height: 1.5, color: Pal.error(context))),
              ]),
            ),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = s.viewDay;
    final allDay = _eventsOf(day).where((e) => e.allDay).toList();
    return Container(
      width: 320,
      decoration: BoxDecoration(
          color: Pal.panel(context), border: Border(left: BorderSide(color: Pal.border(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 0),
          child: Row(children: [
            Expanded(
              child: Text('РАСПИСАНИЕ',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Pal.secondary(context))),
            ),
            IconButton(
                tooltip: 'Новое событие',
                visualDensity: VisualDensity.compact,
                onPressed: _add,
                icon: Icon(Icons.add, size: 20, color: Pal.accent(context))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
          child: Row(children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => s.setViewDay(day.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left, size: 20)),
            Expanded(
              child: InkWell(
                onTap: () => s.setViewDay(DateTime.now()),
                child: Text(fmtDayLong(day),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => s.setViewDay(day.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right, size: 20)),
          ]),
        ),
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Column(children: [
              for (final e in allDay)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SizedBox(height: 40, child: _EventCard(event: e, store: s, onOpen: () => _open(e))),
                ),
            ]),
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
              controller: _sc,
              padding: const EdgeInsets.only(top: 10, bottom: 20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey('${day.year}-${day.month}-${day.day}'),
                  child: _timeline(day),
                ),
              ),
            ),
        ),
      ]),
    );
  }
}

/// Карточка события: пастельный фон, слева цветная полоса; при наведении — тень и лёгкое увеличение.
class _EventCard extends StatefulWidget {
  final CalEvent event;
  final Store store;
  final VoidCallback onOpen;
  const _EventCard({required this.event, required this.store, required this.onOpen});
  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool _hover = false;

  (Color, Color) _colors(bool dark) {
    final e = widget.event;
    final Color strong = e.isTask
        ? const Color(0xFF059669)
        : e.allDay
            ? const Color(0xFFEA580C)
            : const Color(0xFF2563EB);
    final bg = dark
        ? strong.withOpacity(0.20)
        : e.isTask
            ? const Color(0xFFD1FAE5)
            : e.allDay
                ? const Color(0xFFFFEDD5)
                : const Color(0xFFDBEAFE);
    return (bg, strong);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final dark = Pal.dark(context);
    final (bg, strong) = _colors(dark);
    final time = e.allDay
        ? 'весь день'
        : e.isTask
            ? fmtTime(e.startDt)
            : '${fmtTime(e.startDt)} – ${fmtTime(e.endDt)}';
    final tc = dark ? const Color(0xFFFAFAFA) : const Color(0xFF1E293B);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.01 : 1,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: strong, width: 3)),
            boxShadow: _hover ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))] : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.isTask)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 1),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Checkbox(
                        value: e.done,
                        onChanged: (v) {
                          e.done = v ?? false;
                          e.updatedAt = nowMs();
                          widget.store.eventsChanged();
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title.isEmpty ? 'Без названия' : e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: e.done ? Pal.muted(context) : tc,
                            decoration: e.done ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 2),
                    Text(time,
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Pal.secondary(context))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
