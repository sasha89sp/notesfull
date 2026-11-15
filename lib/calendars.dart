import 'package:flutter/material.dart';
import 'ical_sub.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Описание календаря: локальный (хранится только в приложении и в синхронизации ASRbox)
/// или Google (событие связано с аккаунтом Google).
class CalDef {
  String id, name, type; // type: local | google | url (подписка iCal, только чтение)
  String url;
  int color;
  int last; // последнее обновление подписки
  bool visible;
  CalDef({required this.id, required this.name, this.type = 'local', this.color = 0xFF4F46E5, this.visible = true, this.url = '', this.last = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'color': color, 'visible': visible, 'url': url, 'last': last};

  factory CalDef.fromJson(Map<String, dynamic> j) => CalDef(
        id: (j['id'] ?? newId()) as String,
        name: (j['name'] ?? '') as String,
        type: (j['type'] ?? 'local') as String,
        color: (j['color'] ?? 0xFF4F46E5) as int,
        visible: (j['visible'] ?? true) as bool,
        url: (j['url'] ?? '') as String,
        last: (j['last'] ?? 0) as int,
      );
}

/// Работа со списком календарей. «main» (Основной) и «google» всегда существуют.
class Cals {
  static const kColors = [0xFF4F46E5, 0xFF2563EB, 0xFF059669, 0xFFEA580C, 0xFFDC2626, 0xFF9333EA, 0xFF0891B2];

  static List<CalDef> all(Settings st) {
    final l = [for (final m in st.calendars) CalDef.fromJson(Map<String, dynamic>.from(m))];
    if (!l.any((c) => c.id == 'main')) l.insert(0, CalDef(id: 'main', name: 'Основной'));
    if (!l.any((c) => c.id == 'google')) {
      l.insert(1, CalDef(id: 'google', name: 'Google Календарь', type: 'google', color: 0xFF2563EB));
    }
    return l;
  }

  static void save(Settings st, List<CalDef> l) => st.calendars = [for (final c in l) c.toJson()];

  /// Календарь события: явный, иначе по происхождению (Google или основной).
  static String idOf(CalEvent e) => e.calId.isNotEmpty ? e.calId : (e.gId.isNotEmpty ? 'google' : 'main');

  static CalDef of(Settings st, CalEvent e) {
    final id = idOf(e);
    final l = all(st);
    for (final c in l) {
      if (c.id == id) return c;
    }
    return l.first;
  }

  static bool visible(Settings st, CalEvent e) {
    if (st.calendars.isEmpty) return true;
    return of(st, e).visible;
  }

  static Color color(Settings st, CalEvent e) => Color(of(st, e).color);

  /// Подпись для кэшей: меняется при смене набора/видимости календарей.
  static int sig(Settings st) {
    var h = 0;
    for (final m in st.calendars) {
      h = (h * 31 + '${m['id']}${m['visible']}${m['color']}'.hashCode) & 0x3fffffff;
    }
    return h;
  }
}

/// Раздел «Календари» в настройках: видимость, цвет, имя, добавление локальных календарей.
class CalendarsBox extends StatefulWidget {
  final Store s;
  const CalendarsBox({super.key, required this.s});
  @override
  State<CalendarsBox> createState() => _CalendarsBoxState();
}

class _CalendarsBoxState extends State<CalendarsBox> {
  Store get s => widget.s;

  Future<void> _apply(List<CalDef> l) async {
    Cals.save(s.settings, l);
    await s.saveSettings();
    s.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _rename(List<CalDef> l, CalDef c) async {
    final ctl = TextEditingController(text: c.name);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название календаря'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Готово')),
        ],
      ),
    );
    ctl.dispose();
    if (r == null || r.isEmpty) return;
    c.name = r;
    await _apply(l);
  }

  Future<void> _addUrl() async {
    final n = TextEditingController();
    final u = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Онлайн-календарь (iCal)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 8),
          TextField(
              controller: u,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Ссылка .ics или webcal://')),
          const SizedBox(height: 8),
          const Text('Только чтение. Повторяющиеся события показываются первым вхождением.',
              style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
        ],
      ),
    );
    final name = n.text.trim(), url = u.text.trim();
    n.dispose();
    u.dispose();
    if (ok != true || url.isEmpty) return;
    final l = Cals.all(s.settings);
    l.add(CalDef(
        id: newId(),
        name: name.isEmpty ? 'Онлайн ${l.length}' : name,
        type: 'url',
        url: url,
        color: Cals.kColors[l.length % Cals.kColors.length]));
    await _apply(l);
    await IcalSub.syncDue(s, force: true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = Cals.all(s.settings);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Hint('События можно вести в нескольких календарях: локальных (только в ASRbox, синхронизируются '
          'вместе с данными) и Google (онлайн). Галочка — показывать ли календарь в расписании и календаре.'),
      for (final c in l)
        Row(children: [
          Checkbox(
              value: c.visible,
              onChanged: (v) {
                c.visible = v ?? true;
                _apply(l);
              }),
          GestureDetector(
            onTap: () {
              final i = Cals.kColors.indexOf(c.color);
              c.color = Cals.kColors[(i + 1) % Cals.kColors.length];
              _apply(l);
            },
            child: Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(color: Color(c.color), shape: BoxShape.circle)),
          ),
          Expanded(child: Text('${c.name}${c.type == 'google' ? ' (Google, онлайн)' : c.type == 'url' ? ' (iCal, онлайн)' : ''}')),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _rename(l, c)),
          if (c.id != 'main' && c.id != 'google')
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  // события удалённого календаря переходят в «Основной»
                  for (final e in s.events) {
                    if (e.calId == c.id && c.type == 'url') {
                      e.deleted = true;
                      e.updatedAt = nowMs();
                    } else if (e.calId == c.id) {
                      e.calId = 'main';
                      e.updatedAt = nowMs();
                    }
                  }
                  s.eventsChanged();
                  l.remove(c);
                  await _apply(l);
                }),
        ]),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.public, size: 18),
          label: const Text('Онлайн-календарь по ссылке'),
          onPressed: _addUrl,
        ),
        if (l.any((c) => c.type == 'url'))
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Обновить подписки'),
            onPressed: () async {
              await IcalSub.syncDue(s, force: true);
              if (mounted) setState(() {});
            },
          ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Добавить локальный календарь'),
          onPressed: () async {
            l.add(CalDef(
                id: newId(),
                name: 'Календарь ${l.length}',
                color: Cals.kColors[l.length % Cals.kColors.length]));
            await _apply(l);
          },
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }
}
