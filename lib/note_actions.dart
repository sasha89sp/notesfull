import 'dart:convert';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'ctx_menu.dart';
import 'models.dart';
import 'pdf_export.dart';
import 'store.dart';
import 'util.dart';

/// Действия над заметками и папками для контекстного меню десктопного вида.
class NoteActions {
  final BuildContext context;
  final Store s;
  NoteActions(this.context, this.s);

  Future<String?> askName(String title, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Готово')),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  List<MapEntry<NoteFolder, int>> _flat(String parent, int depth, String? exclude) {
    final out = <MapEntry<NoteFolder, int>>[];
    for (final f in s.childFolders(parent)) {
      if (f.id == exclude) continue;
      out.add(MapEntry(f, depth));
      out.addAll(_flat(f.id, depth + 1, exclude));
    }
    return out;
  }

  /// Выбор папки: id, '' — корень, null — отмена.
  Future<String?> pickFolder({String? exclude}) {
    final flat = _flat('', 0, exclude);
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Переместить в папку'),
        children: [
          ListTile(
              dense: true,
              leading: const Icon(Icons.home_outlined),
              title: const Text('Без папки (корень)'),
              onTap: () => Navigator.pop(ctx, '')),
          for (final e in flat)
            Padding(
              padding: EdgeInsets.only(left: 16.0 * e.value),
              child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(e.key.name),
                  onTap: () => Navigator.pop(ctx, e.key.id)),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ заметка

  List<CtxItem> noteItems(Note n) => [
        const CtxItem('open', 'Открыть', icon: Icons.open_in_new),
        CtxItem('fav', n.favorite ? 'Убрать из избранного' : 'В избранное',
            icon: n.favorite ? Icons.star : Icons.star_border),
        CtxItem('pin', s.isPinned(n.id) ? 'Открепить с главной' : 'Закрепить на главной',
            icon: s.isPinned(n.id) ? Icons.push_pin : Icons.push_pin_outlined),
        if (!n.isGroup) const CtxItem('mv', 'Переместить в папку…', icon: Icons.drive_file_move_outlined),
        const CtxItem('md', 'Экспорт в Markdown', icon: Icons.upload_file),
        const CtxItem('pdf', 'Экспорт в PDF', icon: Icons.picture_as_pdf_outlined),
        const CtxItem('-', ''),
        const CtxItem('del', 'Удалить в корзину', icon: Icons.delete_outline, danger: true),
      ];

  /// Выполняет действие; возвращает 'open' / 'deleted' / null, чтобы вызывающий мог обновить выбор.
  Future<String?> runNote(Note n, String act) async {
    switch (act) {
      case 'open':
        return 'open';
      case 'fav':
        n.favorite = !n.favorite;
        n.updatedAt = nowMs();
        s.changed();
        break;
      case 'pin':
        s.togglePin(n.id);
        break;
      case 'mv':
        final to = await pickFolder();
        if (to != null) s.moveNote(n, to);
        break;
      case 'pdf':
        try {
          final name = n.title.isEmpty ? 'note' : n.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final ok = await saveBytes('$name.pdf', await PdfExport.build(s, [n]));
          if (ok && context.mounted) toast(context, 'PDF сохранён');
        } catch (e) {
          if (context.mounted) toast(context, 'Ошибка PDF: $e');
        }
        break;
      case 'md':
        try {
          final name = n.title.isEmpty ? 'note' : n.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final ok = n.attachmentIds().any(s.hasAttachment)
              ? await saveBytes('$name.zip', await Jex.exportMarkdown(s, [n]))
              : await saveBytes('$name.md', utf8.encode('# ${n.title}\n\n${Jex.bodyOf(n, (b) => null)}\n'));
          if (ok && context.mounted) toast(context, 'Экспортировано');
        } catch (e) {
          if (context.mounted) toast(context, 'Ошибка экспорта: $e');
        }
        break;
      case 'del':
        n.deleted = true;
        n.updatedAt = nowMs();
        s.changed();
        return 'deleted';
    }
    return null;
  }

  // ------------------------------------------------------------ папка

  List<CtxItem> folderItems(NoteFolder f) => [
        const CtxItem('sub', 'Новая подпапка', icon: Icons.create_new_folder_outlined),
        const CtxItem('ren', 'Переименовать', icon: Icons.edit_outlined),
        const CtxItem('mv', 'Переместить…', icon: Icons.drive_file_move_outlined),
        CtxItem('fav', s.isFolderFav(f.id) ? 'Убрать из избранного' : 'В избранное',
            icon: s.isFolderFav(f.id) ? Icons.star : Icons.star_border),
        CtxItem('pin', s.isPinned(f.id) ? 'Открепить с главной' : 'Закрепить на главной',
            icon: s.isPinned(f.id) ? Icons.push_pin : Icons.push_pin_outlined),
        const CtxItem('-', ''),
        const CtxItem('del', 'Удалить папку (заметки сохранятся)', icon: Icons.delete_outline, danger: true),
      ];

  Future<void> runFolder(NoteFolder f, String act) async {
    switch (act) {
      case 'sub':
        final n = await askName('Новая подпапка');
        if (n != null) s.addFolder(n, f.id);
        break;
      case 'ren':
        final n = await askName('Переименовать папку', f.name);
        if (n != null) s.renameFolder(f, n);
        break;
      case 'mv':
        final to = await pickFolder(exclude: f.id);
        if (to != null) s.moveFolder(f, to);
        break;
      case 'fav':
        s.toggleFolderFav(f.id);
        break;
      case 'pin':
        s.togglePin(f.id);
        break;
      case 'del':
        s.deleteFolder(f);
        break;
    }
  }
}
