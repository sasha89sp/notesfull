import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

class EventScreen extends StatefulWidget {
  final Store store;
  final CalEvent event;
  final bool isNew;
  const EventScreen(
      {super.key, required this.store, required this.event, required this.isNew});
  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  late int _remind;

  CalEvent get e => widget.event;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: e.title);
    _notes = TextEditingController(text: e.notes);
    _start = e.startDt;
    _end = e.endDt;
    _allDay = e.allDay;
    _remind = e.remind;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final cur = start ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      final n = DateTime(d.year, d.month, d.day, cur.hour, cur.minute);
      if (start) {
        final len = _end.difference(_start);
        _start = n;
        _end = n.add(len);
      } else {
        _end = n;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final cur = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute),
    );
    if (t == null) return;
    setState(() {
      final n = DateTime(cur.year, cur.month, cur.day, t.hour, t.minute);
      if (start) {
        final len = _end.difference(_start);
        _start = n;
        _end = n.add(len);
      } else {
        _end = n;
      }
    });
  }

  void _save() {
    var end = _end;
    if (end.isBefore(_start)) end = _start;
    e.title = _title.text.trim();
    e.notes = _notes.text;
    e.start = _start.millisecondsSinceEpoch;
    e.end = (e.isTask ? _start : end).millisecondsSinceEpoch;
    e.allDay = _allDay;
    e.remind = _remind;
    e.updatedAt = nowMs();
    if (widget.isNew) widget.store.events.add(e);
    widget.store.eventsChanged();
    Navigator.pop(context);
  }

  void _delete() {
    e.deleted = true;
    e.updatedAt = nowMs();
    if (widget.isNew) {
      Navigator.pop(context);
      return;
    }
    widget.store.eventsChanged();
    Navigator.pop(context);
  }

  Widget _dtRow(String label, bool start) {
    final d = start ? _start : _end;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: () => _pickDate(start), child: Text(fmtDay(d))),
        if (!_allDay)
          TextButton(onPressed: () => _pickTime(start), child: Text(fmtTime(d))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const opts = <int, String>{
      -1: 'Нет',
      0: 'В момент начала',
      5: 'За 5 минут',
      15: 'За 15 минут',
      30: 'За 30 минут',
      60: 'За 1 час',
      1440: 'За 1 день',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(e.isTask ? 'Задача' : 'Событие'),
        actions: [
          if (!widget.isNew)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.isNew,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'Название'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Весь день'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          _dtRow(e.isTask ? 'Срок' : 'Начало', true),
          if (!e.isTask) _dtRow('Конец', false),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Напоминание'),
            trailing: DropdownButton<int>(
              value: opts.containsKey(_remind) ? _remind : -1,
              items: [
                for (final o in opts.entries)
                  DropdownMenuItem(value: o.key, child: Text(o.value)),
              ],
              onChanged: (v) => setState(() => _remind = v ?? -1),
            ),
          ),
          if (e.isTask)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Выполнено'),
              value: e.done,
              onChanged: (v) => setState(() => e.done = v ?? false),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Заметки'),
          ),
          if (e.gId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Синхронизировано с Google Календарём',
                  style: TextStyle(color: Pal.secondary(context), fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
