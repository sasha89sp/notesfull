// ▸ Блок заметки «Календарь (.ics)»: файл календаря открыт списком, одно событие — одна строка
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'calendars.dart';
import 'ics.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

part 'ics_block_2.dart';


/// Блок заметки «Календарь (.ics)»: файл календаря открыт списком, одно событие — одна строка
/// «дата · текст». Нажатие на дату раскрывает все свойства VEVENT для правки.
/// Содержимое блока (Block.content) — сам текст .ics, поэтому он едет через обычную синхронизацию.
class IcsBlockView extends StatefulWidget {
  final Store store;
  final Block block;
  final VoidCallback onChanged;
  const IcsBlockView({super.key, required this.store, required this.block, required this.onChanged});
  @override
  State<IcsBlockView> createState() => _IcsBlockViewState();
}

class _IcsBlockViewState extends State<IcsBlockView> {
  late List<Map<String, String>> _ev;
  final Set<Map<String, String>> _open = {};
  final Map<String, TextEditingController> _ctl = {};

  static const _common = ['SUMMARY', 'LOCATION', 'DESCRIPTION', 'RRULE', 'STATUS', 'CATEGORIES', 'URL', 'ORGANIZER'];
  static const _labels = {
    'SUMMARY': 'Название (SUMMARY)',
    'LOCATION': 'Место (LOCATION)',
    'DESCRIPTION': 'Описание (DESCRIPTION)',
    'RRULE': 'Повтор (RRULE)',
    'STATUS': 'Статус (STATUS)',
    'CATEGORIES': 'Категории (CATEGORIES)',
    'URL': 'Ссылка (URL)',
    'ORGANIZER': 'Организатор (ORGANIZER)',
    'UID': 'Идентификатор (UID)',
  };

  @override
  void initState() {
    super.initState();
    _ev = IcsRaw.parse(b.content);
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._ev]..sort((a, c) =>
        (IcsRaw.start(a)?.millisecondsSinceEpoch ?? 0).compareTo(IcsRaw.start(c)?.millisecondsSinceEpoch ?? 0));
    final acc = Pal.accent(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 4, children: [
        TextButton.icon(onPressed: _import, icon: const Icon(Icons.file_open_outlined, size: 18), label: const Text('Импорт .ics')),
        TextButton.icon(onPressed: _ev.isEmpty ? null : _export, icon: const Icon(Icons.save_alt, size: 18), label: const Text('Экспорт .ics')),
        TextButton.icon(onPressed: _ev.isEmpty ? null : _toCalendars, icon: const Icon(Icons.event_available_outlined, size: 18), label: const Text('В мои календари')),
        TextButton.icon(onPressed: _addNew, icon: const Icon(Icons.add, size: 18), label: const Text('Событие')),
      ]),
      if (_ev.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Файл календаря пуст: импортируйте .ics или добавьте событие.',
              style: TextStyle(color: Pal.secondary(context))),
        ),
      for (final m in sorted) ...[
        InkWell(
          onTap: () => setState(() => _open.contains(m) ? _open.remove(m) : _open.add(m)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: acc.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(_dateLabel(m),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: acc)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      IcsRaw.text(IcsRaw.get(m, 'SUMMARY') ?? '').isEmpty ? '(без названия)' : IcsRaw.text(IcsRaw.get(m, 'SUMMARY') ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              Icon(_open.contains(m) ? Icons.expand_less : Icons.expand_more, size: 18, color: Pal.muted(context)),
            ]),
          ),
        ),
        if (_open.contains(m)) _editor(m),
      ],
    ]);
  }}