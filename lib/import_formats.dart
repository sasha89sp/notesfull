// ▸ Реестр форматов импорта (JEX, RAW, ENEX, HTML, MD, MD+Front Matter, Obsidian, TXT, ONE) и запуск импорта с выбором файла/каталога
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'applog.dart';
import 'backup.dart';
import 'import_model.dart';
import 'import_parsers.dart';
import 'store.dart';
import 'util.dart';

/// Формат импорта заметок. Список [kImportFormats] — реестр: чтобы добавить формат,
/// достаточно новой записи и ветки в [Importer.run].
class ImportFormat {
  final String id; // уникальный
  final String kind; // jex | raw | enex | html | md | mdfm | obsidian | txt | one
  final String label;
  final bool dir; // импортируется каталог, а не файлы
  final List<String> exts; // допустимые расширения файла
  const ImportFormat(this.id, this.kind, this.label, {this.dir = false, this.exts = const []});
}

const kImportFormats = <ImportFormat>[
  ImportFormat('jex', 'jex', 'JEX - Файл экспорта Joplin', exts: ['jex', 'tar']),
  ImportFormat('raw', 'raw', 'RAW - Каталог экспорта Joplin', dir: true),
  // группа 2
  ImportFormat('enex_html', 'enex', 'ENEX - Файл экспорта Evernote (HTML)', exts: ['enex']),
  ImportFormat('enex_md', 'enex', 'ENEX - Файл экспорта Evernote (Markdown)', exts: ['enex']),
  ImportFormat('enex_html_dir', 'enex', 'ENEX - Каталог с файлами экспорта Evernote (HTML)', dir: true),
  ImportFormat('enex_md_dir', 'enex', 'ENEX - Каталог с файлами экспорта Evernote (Markdown)', dir: true),
  ImportFormat('html', 'html', 'HTML - HTML документ (Файл)', exts: ['html', 'htm']),
  ImportFormat('html_dir', 'html', 'HTML - HTML документ (Каталог)', dir: true),
  ImportFormat('md', 'md', 'MD - Markdown (Файл)', exts: ['md', 'markdown']),
  ImportFormat('md_dir', 'md', 'MD - Markdown (Каталог)', dir: true),
  ImportFormat('mdfm', 'mdfm', 'MD - Markdown + Front Matter (Файл)', exts: ['md', 'markdown']),
  ImportFormat('mdfm_dir', 'mdfm', 'MD - Markdown + Front Matter (Каталог)', dir: true),
  ImportFormat('obsidian', 'obsidian', 'OBSIDIAN - Obsidian Vault', dir: true),
  ImportFormat('txt', 'txt', 'TXT - Текстовый документ (Файл)', exts: ['txt']),
  ImportFormat('txt_dir', 'txt', 'TXT - Текстовый документ (Каталог)', dir: true),
  ImportFormat('one', 'one', 'ONE - Блокнот OneNote', exts: ['one']),
];

/// Первые две записи (Joplin) отделяются в меню чертой от остальных.
const kImportJoplinCount = 2;

class Importer {
  /// «Другие приложения…»: подсказка, как перенести данные из прочих программ.
  static Future<void> others(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Другие приложения'),
          content: const Text('Если вашего приложения нет в списке, экспортируйте из него заметки в один из '
              'форматов: Markdown, HTML, TXT или ENEX (Evernote) — и импортируйте так же. '
              'Для OneNote: экспорт блокнота в HTML (или через Evernote Importer в ENEX).'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
        ),
      );

  static Future<void> run(BuildContext context, Store s, ImportFormat f) async {
    if (f.kind == 'one') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('OneNote (.one)'),
          content: const Text('Файлы .one — закрытый бинарный формат Microsoft, прочитать его без OneNote нельзя. '
              'Откройте блокнот в OneNote и экспортируйте страницы в HTML (или перенесите в Evernote '
              'и сохраните ENEX), затем импортируйте этот файл или каталог.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))],
        ),
      );
      return;
    }
    List<String> paths;
    try {
      if (f.dir) {
        final d = await FilePicker.platform.getDirectoryPath(dialogTitle: f.label);
        if (d == null) return;
        paths = [d];
      } else {
        final r = await FilePicker.platform
            .pickFiles(type: FileType.any, allowMultiple: f.kind != 'jex', dialogTitle: f.label);
        if (r == null || r.files.isEmpty) return;
        paths = [for (final x in r.files) if (x.path != null) x.path!];
        final bad = paths.where((p) => !f.exts.contains(p.split('.').last.toLowerCase())).toList();
        if (bad.isNotEmpty) {
          if (context.mounted) toast(context, 'Нужен файл .${f.exts.join(' / .')}');
          return;
        }
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Не удалось открыть выбор: $e');
      return;
    }
    if (!context.mounted) return;

    final note = ValueNotifier<String>('Импорт…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder<String>(valueListenable: note, builder: (_, v, __) => Text(v))),
        ]),
      ),
    );
    String msg;
    try {
      note.value = 'Страховочная копия…';
      await Backup.safetyCopy(s, 'import');
      note.value = 'Чтение…';
      if (f.kind == 'jex') {
        msg = await JexIo.importInto(s, await File(paths.first).readAsBytes(), progress: (t) => note.value = t);
      } else if (f.kind == 'raw') {
        final tar = await compute(rawDirToTar, paths.first);
        msg = await JexIo.importInto(s, tar, progress: (t) => note.value = t);
      } else {
        final list = await compute(impParse, ImpJob(f.kind, paths, f.dir));
        if (list.isEmpty) {
          msg = 'в выбранном месте не найдено подходящих файлов';
        } else {
          msg = await commitImport(s, list, progress: (t) => note.value = t);
        }
      }
      AppLog.I.i('import', '${f.label}: $msg');
    } catch (e, stk) {
      AppLog.I.e('import', '${f.label}: $e', stk);
      msg = 'ошибка — $e';
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      toast(context, 'Импорт: $msg');
    }
  }

  /// Список форматов в окне (для телефона и настроек).
  static Future<void> pick(BuildContext context, Store s) async {
    final f = await showDialog<ImportFormat>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Импорт заметок'),
        children: [
          for (final x in kImportFormats)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, x), child: Text(x.label)),
          SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                others(context);
              },
              child: const Text('Другие приложения…')),
        ],
      ),
    );
    if (f != null && context.mounted) await run(context, s, f);
  }
}
