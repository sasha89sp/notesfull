import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Левая панель компьютерного вида (260 px): «Новая заметка», мини-календарь,
/// навигация по календарю, модули, папки со счётчиками, служебные пункты.
class Sidebar extends StatefulWidget {
  final Store s;
  final String tab;
  final List<String> mods;
  final Map<String, String> names;
  final Map<String, IconData> icons;
  final void Function(String module) go;
  final VoidCallback newNote, settings, trash, toggleTheme, toPhoneView;
  final void Function(String folderId) openFolder;
  const Sidebar({
    super.key,
    required this.s,
    required this.tab,
    required this.mods,
    required this.names,
    required this.icons,
    required this.go,
    required this.newNote,
    required this.settings,
    required this.trash,
    required this.toggleTheme,
    required this.toPhoneView,
    required this.openFolder,
  });
  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  Store get s => widget.s;

  Widget _item(IconData? icon, String label, VoidCallback f,
      {bool sel = false, String? badge, String? emoji, double size = 14}) {
    final acc = Pal.accent(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: f,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? Pal.border(context) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          if (emoji != null)
            Text(emoji, style: const TextStyle(fontSize: 14))
          else if (icon != null)
            Icon(icon, size: 16, color: sel ? acc : Pal.secondary(context)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: size, fontWeight: sel ? FontWeight.w500 : FontWeight.w400))),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Pal.sidebar(context), borderRadius: BorderRadius.circular(10)),
              child: Text(badge, style: TextStyle(fontSize: 11, color: Pal.secondary(context))),
            ),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Pal.muted(context))),
      );

  // ------------------------------------------------------------ сборка

  @override
  Widget build(BuildContext context) {
    final mods = widget.mods.where((m) => !(m == 'home' && s.settings.moduleOn('notes'))).toList();
    final hasCal = widget.mods.contains('calendar');
    final calTab = widget.tab == 'calendar';
    // счётчики заметок по папкам верхнего уровня (включая вложенные)
    final parentOf = {for (final f in s.folders) f.id: f.parent};
    String rootOf(String id) {
      var x = id;
      for (var i = 0; i < 20 && parentOf[x] != null && parentOf[x]!.isNotEmpty; i++) {
        x = parentOf[x]!;
      }
      return x;
    }

    final counts = <String, int>{};
    if (s.settings.moduleOn('notes')) {
      for (final n in s.notes) {
        if (n.deleted || n.isGroup || n.folder.isEmpty) continue;
        final r = rootOf(n.folder);
        counts[r] = (counts[r] ?? 0) + 1;
      }
    }
    final folders = s.settings.moduleOn('notes')
        ? (s.folders.where((f) => !f.deleted && f.parent.isEmpty).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
        : <NoteFolder>[];
    final dark = Pal.dark(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Pal.sidebar(context).withOpacity(0.85),
        border: Border(right: BorderSide(color: Pal.border(context))),
      ),
      child: Column(children: [
        if (s.settings.moduleOn('notes'))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Material(
              color: Pal.panel(context),
              borderRadius: BorderRadius.circular(8),
              elevation: dark ? 0 : 0.5,
              shadowColor: const Color(0x14000000),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.newNote,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8), border: Border.all(color: Pal.border(context))),
                  child: Row(children: [
                    Icon(Icons.add, size: 16, color: Pal.accent(context)),
                    const SizedBox(width: 8),
                    const Text('Новая заметка', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
            if (hasCal) ...[
              const SizedBox(height: 4),
              _item(Icons.today_outlined, 'Сегодня', () {
                s.setViewDay(DateTime.now(), view: 'day');
                widget.go('calendar');
              }, sel: calTab && s.calView == 'day' && sameDay(s.viewDay, DateTime.now())),
              _item(Icons.view_week_outlined, 'Неделя', () {
                s.setViewDay(s.viewDay, view: 'week');
                widget.go('calendar');
              }, sel: calTab && s.calView == 'week'),
              _item(Icons.calendar_view_month_outlined, 'Месяц', () {
                s.setViewDay(s.viewDay, view: 'month');
                widget.go('calendar');
              }, sel: calTab && s.calView == 'month'),
              _item(Icons.calendar_today_outlined, 'Год', () {
                s.setViewDay(s.viewDay, view: 'year');
                widget.go('calendar');
              }, sel: calTab && s.calView == 'year'),
            ],
            _label('РАЗДЕЛЫ'),
            for (final m in mods)
              _item(widget.icons[m], widget.names[m] ?? m, () => widget.go(m),
                  sel: widget.tab == m || (m == 'notes' && widget.tab == 'home')),
            if (folders.isNotEmpty) _label('ПАПКИ'),
            for (final f in folders)
              _item(null, f.name, () => widget.openFolder(f.id),
                  emoji: '📁', badge: (counts[f.id] ?? 0) > 0 ? '${counts[f.id]}' : null),
          ]),
        ),
        Divider(height: 1, color: Pal.border(context)),
        const SizedBox(height: 4),
        if (s.settings.moduleOn('notes')) _item(Icons.delete_outline, 'Корзина', widget.trash, size: 13),
        _item(Icons.settings_outlined, 'Настройки', widget.settings, size: 13),
        _item(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, dark ? 'Светлая тема' : 'Тёмная тема',
            widget.toggleTheme, size: 13),
        _item(Icons.smartphone, 'Вид: телефон', widget.toPhoneView, size: 13),
        const SizedBox(height: 6),
      ]),
    );
  }
}
