import 'dart:io';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'diag_screens.dart';
import 'import_formats.dart';
import 'models.dart';
import 'note_actions.dart';
import 'pdf_export.dart';
import 'store.dart';
import 'util.dart';

/// Действия верхнего меню компьютерного вида (подставляются оболочкой).
class MenuHandlers {
  final void Function(String module) go;
  final VoidCallback newNote, newEvent, newTask, settings, trash, switchProfile, toPhoneView, toggleTheme;
  MenuHandlers({
    required this.go,
    required this.newNote,
    required this.newEvent,
    required this.newTask,
    required this.settings,
    required this.trash,
    required this.switchProfile,
    required this.toPhoneView,
    required this.toggleTheme,
  });
}

/// Верхнее меню как в Joplin: Файл · Вид · Переход · Блокноты · Заметка · Сервис · Помощь.
class AppMenu extends StatelessWidget {
  final Store s;
  final List<String> mods;
  final Map<String, String> names;
  final MenuHandlers h;
  const AppMenu({super.key, required this.s, required this.mods, required this.names, required this.h});

  Widget _item(String label, VoidCallback f, {String? key}) => MenuItemButton(
        onPressed: f,
        trailingIcon: key == null ? null : Text(key, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
        child: Text(label),
      );

  void _zoom(double d) {
    s.settings.fontScale = d == 0 ? 1.0 : (s.settings.fontScale + d).clamp(0.7, 1.6);
    s.saveSettings();
    s.refresh();
  }

  Future<void> _export(BuildContext c, String kind) async {
    try {
      final notes = s.notes.where((n) => !n.isGroup && !n.deleted).toList();
      final ok = kind == 'jex'
          ? await saveBytes('asrbox.jex', await Jex.exportFrom(s))
          : kind == 'md'
              ? await saveBytes('asrbox_markdown.zip', await Jex.exportMarkdown(s, notes))
              : await saveBytes('asrbox_notes.pdf', await PdfExport.build(s, notes));
      if (ok && c.mounted) toast(c, 'Экспорт сохранён');
    } catch (e) {
      if (c.mounted) toast(c, 'Ошибка экспорта: $e');
    }
  }

  Future<void> _newFolder(BuildContext c) async {
    final n = await NoteActions(c, s).askName('Новый блокнот');
    if (n == null || n.trim().isEmpty) return;
    s.folders.add(NoteFolder.create(n.trim(), ""));
    s.foldersChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mid = <Widget>[
      for (var i = 0; i < kImportFormats.length; i++) ...[
        if (i == kImportJoplinCount) const Divider(height: 1),
        _item(kImportFormats[i].label, () => Importer.run(context, s, kImportFormats[i])),
      ],
      const Divider(height: 1),
      _item('Другие приложения…', () => Importer.others(context)),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: MenuBar(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(bg),
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
        ),
        children: [
          SubmenuButton(menuChildren: [
            _item('Новая заметка', h.newNote, key: 'Ctrl+N'),
            _item('Новая задача', h.newTask),
            _item('Новое событие', h.newEvent),
            _item('Новый блокнот', () => _newFolder(context)),
            const Divider(height: 1),
            SubmenuButton(menuChildren: mid, child: const Text('Импорт')),
            SubmenuButton(menuChildren: [
              _item('JEX - Файл экспорта Joplin', () => _export(context, 'jex')),
              _item('Markdown (архив .zip)', () => _export(context, 'md')),
              _item('PDF - все заметки', () => _export(context, 'pdf')),
            ], child: const Text('Экспортировать все')),
            const Divider(height: 1),
            _item('Синхронизировать', () => s.syncAll(), key: 'Ctrl+S'),
            _item('Переключение профиля', h.switchProfile),
            const Divider(height: 1),
            _item('Выход', () => exit(0), key: 'Ctrl+Q'),
          ], child: const Text('Файл')),
          SubmenuButton(menuChildren: [
            _item('Вид «Телефон»', h.toPhoneView),
            _item(s.settings.showSchedule ? 'Скрыть «Расписание»' : 'Показать «Расписание»', () {
              s.settings.showSchedule = !s.settings.showSchedule;
              s.saveSettings();
              s.refresh();
            }),
            _item(dark ? 'Светлая тема' : 'Тёмная тема', h.toggleTheme),
            const Divider(height: 1),
            _item('Увеличить масштаб', () => _zoom(0.1), key: 'Ctrl++'),
            _item('Уменьшить масштаб', () => _zoom(-0.1), key: 'Ctrl+−'),
            _item('Сбросить масштаб', () => _zoom(0), key: 'Ctrl+0'),
            const Divider(height: 1),
            _item('Сбросить расположение блоков', () {
              s.settings.paneOrder = ['side', 'list', 'detail'];
              s.settings.paneW = {'side': 230, 'list': 330};
              s.saveSettings();
              s.refresh();
            }),
          ], child: const Text('Вид')),
          SubmenuButton(menuChildren: [
            for (final m in mods) _item(names[m] ?? m, () => h.go(m)),
          ], child: const Text('Переход')),
          SubmenuButton(menuChildren: [
            _item('Новый блокнот', () => _newFolder(context)),
            _item('Корзина', h.trash),
          ], child: const Text('Блокноты')),
          SubmenuButton(menuChildren: [
            _item('Новая заметка', h.newNote),
            _item('Новая задача', h.newTask),
            _item('Новое событие', h.newEvent),
          ], child: const Text('Заметка')),
          SubmenuButton(menuChildren: [
            _item('Настройки', h.settings),
            _item('История синхронизации', () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => SyncHistoryScreen(store: s)))),
            _item('Журнал ошибок', () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => LogScreen(store: s)))),
          ], child: const Text('Сервис')),
          SubmenuButton(menuChildren: [
            _item('О программе', () => showAboutDialog(
                context: context,
                applicationName: 'ASRbox',
                applicationVersion: '0.2.0',
                children: const [Text('Зашифрованные заметки, календарь, пароли и общие папки.')])),
          ], child: const Text('Помощь')),
        ],
      ),
    );
  }
}
