import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'event_screen.dart';
import 'calendars.dart';
import 'ics.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

part 'calendar_page_2.dart';
part 'calendar_page_3.dart';


class CalendarPage extends StatefulWidget {
  final Store store;
  const CalendarPage({super.key, required this.store});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {

  // Индекс «день → события» строится один раз за перерисовку (а не на каждую ячейку).
  Map<int, List<CalEvent>> _idx = {};
  int _idxSig = -1;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        // индекс «день → события» пересобираем только когда события менялись
        var sig = s.events.length + Cals.sig(s.settings);
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
  }}