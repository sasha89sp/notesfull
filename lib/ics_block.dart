import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'calendars.dart';
import 'ics.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

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

  Block get b => widget.block;
  Store get s => widget.store;

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

  void _commit() {
    b.content = _ev.isEmpty ? '' : IcsRaw.build(_ev);
    widget.onChanged();
    setState(() {});
  }

  String _dateLabel(Map<String, String> m) {
    final d = IcsRaw.start(m);
    if (d == null) return 'без даты';
    return IcsRaw.isAllDay(m) ? fmtDay(d) : '${fmtDay(d)} ${two(d.hour)}:${two(d.minute)}';
  }

  TextEditingController _c(Map<String, String> m, String key, String text) =>
      _ctl.putIfAbsent('${identityHashCode(m)}|$key', () => TextEditingController(text: text));

  Future<void> _pickDate(Map<String, String> m, String prop) async {
    final cur = (prop == 'DTSTART' ? IcsRaw.start(m) : IcsRaw.end(m)) ?? IcsRaw.start(m) ?? DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: cur, firstDate: DateTime(1990), lastDate: DateTime(2100));
    if (d == null) return;
    final all = IcsRaw.isAllDay(m);
    final n = all ? d : DateTime(d.year, d.month, d.day, cur.hour, cur.minute);
    if (prop == 'DTSTART') {
      final len = (IcsRaw.end(m) ?? cur).difference(cur);
      IcsRaw.setDate(m, 'DTSTART', n, all);
      IcsRaw.setDate(m, 'DTEND', n.add(len), all);
    } else {
      IcsRaw.setDate(m, 'DTEND', n, all);
    }
    _commit();
  }

  Future<void> _pickTime(Map<String, String> m, String prop) async {
    final cur = (prop == 'DTSTART' ? IcsRaw.start(m) : IcsRaw.end(m)) ?? IcsRaw.start(m) ?? DateTime.now();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute));
    if (t == null) return;
    final n = DateTime(cur.year, cur.month, cur.day, t.hour, t.minute);
    if (prop == 'DTSTART') {
      final len = (IcsRaw.end(m) ?? cur).difference(cur);
      IcsRaw.setDate(m, 'DTSTART', n, false);
      IcsRaw.setDate(m, 'DTEND', n.add(len), false);
    } else {
      IcsRaw.setDate(m, 'DTEND', n, false);
    }
    _commit();
  }

  void _setAllDay(Map<String, String> m, bool v) {
    final st = IcsRaw.start(m) ?? DateTime.now();
    final en = IcsRaw.end(m) ?? st;
    if (v) {
      IcsRaw.setDate(m, 'DTSTART', DateTime(st.year, st.month, st.day), true);
      IcsRaw.setDate(m, 'DTEND', DateTime(en.year, en.month, en.day), true);
    } else {
      final s0 = DateTime(st.year, st.month, st.day, 9);
      IcsRaw.setDate(m, 'DTSTART', s0, false);
      IcsRaw.setDate(m, 'DTEND', s0.add(const Duration(hours: 1)), false);
    }
    _commit();
  }

  Widget _dateRow(Map<String, String> m, String prop, String label) {
    final d = prop == 'DTSTART' ? IcsRaw.start(m) : IcsRaw.end(m);
    final all = IcsRaw.isAllDay(m);
    return Row(children: [
      SizedBox(width: 64, child: Text(label, style: TextStyle(fontSize: 13, color: Pal.secondary(context)))),
      TextButton(
          onPressed: () => _pickDate(m, prop), child: Text(d == null ? 'дата' : fmtDay(d))),
      if (!all)
        TextButton(
            onPressed: () => _pickTime(m, prop),
            child: Text(d == null ? 'время' : '${two(d.hour)}:${two(d.minute)}')),
    ]);
  }

  Widget _prop(Map<String, String> m, String key) {
    final n = IcsRaw.name(key);
    final isText = n == 'SUMMARY' || n == 'DESCRIPTION' || n == 'LOCATION';
    final raw = m[key] ?? '';
    final c = _c(m, key, isText ? IcsRaw.text(raw) : raw);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: c,
            maxLines: n == 'DESCRIPTION' ? null : 1,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
                isDense: true, labelText: _labels[n] ?? key),
            onChanged: (v) {
              m[key] = isText ? IcsRaw.esc(v) : v;
              b.content = IcsRaw.build(_ev);
              widget.onChanged();
              // подпись строки обновляем без пересборки полей ввода
              setState(() {});
            },
          ),
        ),
        if (n != 'SUMMARY' && n != 'UID')
          IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Убрать свойство',
              onPressed: () {
                m.remove(key);
                _ctl.remove('${identityHashCode(m)}|$key')?.dispose();
                _commit();
              }),
      ]),
    );
  }

  Widget _editor(Map<String, String> m) {
    final handled = {'DTSTART', 'DTEND', 'DTSTAMP'};
    final keys = m.keys.where((k) => !handled.contains(IcsRaw.name(k))).toList();
    final missing = _common.where((c) => !keys.any((k) => IcsRaw.name(k) == c)).toList();
    return Container(
      margin: const EdgeInsets.only(left: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
      decoration: BoxDecoration(
          color: Pal.card3(context), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Весь день'),
          value: IcsRaw.isAllDay(m),
          onChanged: (v) => _setAllDay(m, v),
        ),
        _dateRow(m, 'DTSTART', 'Начало'),
        _dateRow(m, 'DTEND', 'Конец'),
        const SizedBox(height: 4),
        for (final k in keys) _prop(m, k),
        Row(children: [
          if (missing.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Добавить свойство',
              onSelected: (v) {
                m[v] = '';
                _commit();
              },
              itemBuilder: (_) => [for (final c in missing) PopupMenuItem(value: c, child: Text(_labels[c] ?? c))],
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 16, color: Pal.accent(context)),
                  Text(' свойство', style: TextStyle(color: Pal.accent(context), fontSize: 13)),
                ]),
              ),
            ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Удалить событие'),
            onPressed: () {
              _ev.remove(m);
              _open.remove(m);
              _commit();
            },
          ),
        ]),
      ]),
    );
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ics'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final list = IcsRaw.parse(utf8.decode(r.files.first.bytes!, allowMalformed: true));
    _ev.addAll(list);
    _commit();
    if (mounted) toast(context, 'Добавлено событий: ${list.length}');
  }

  Future<void> _export() async {
    if (await saveBytes('calendar.ics', utf8.encode(IcsRaw.build(_ev))) && mounted) toast(context, 'Файл сохранён');
  }

  void _addNew() {
    final now = DateTime.now();
    final st = DateTime(now.year, now.month, now.day, now.hour + 1);
    final m = <String, String>{'UID': '${newId()}@asrbox', 'SUMMARY': ''};
    IcsRaw.setDate(m, 'DTSTART', st, false);
    IcsRaw.setDate(m, 'DTEND', st.add(const Duration(hours: 1)), false);
    _ev.add(m);
    _open.add(m);
    _commit();
  }

  Future<void> _toCalendars() async {
    final cals = Cals.all(s.settings).where((c) => c.type == 'local').toList();
    var pick = cals.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Добавить в мой календарь'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('События (${_ev.length}) будут добавлены; ранее добавленные из этого файла обновятся.'),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: pick,
              items: [for (final c in cals) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => set(() => pick = v ?? pick),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    var added = 0, updated = 0;
    for (final m in _ev) {
      final e = IcsRaw.toCal(m, calId: pick);
      if (e == null) continue;
      final i = s.events.indexWhere((x) => x.id == e.id);
      if (i >= 0) {
        s.events[i]
          ..title = e.title
          ..notes = e.notes
          ..start = e.start
          ..end = e.end
          ..allDay = e.allDay
          ..calId = pick
          ..deleted = false
          ..updatedAt = nowMs();
        updated++;
      } else {
        s.events.add(e);
        added++;
      }
    }
    s.eventsChanged();
    if (mounted) toast(context, 'Добавлено: $added, обновлено: $updated');
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
  }
}
