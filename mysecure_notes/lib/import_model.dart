import 'dart:typed_data';
import 'models.dart';
import 'store.dart';

/// Вложение, найденное при импорте.
class ImpRes {
  final String id, name, mime;
  final Uint8List bytes;
  ImpRes(this.id, this.name, this.mime, this.bytes);
}

/// Заметка в промежуточном виде: Markdown-текст, ссылки на вложения вида `:/id`.
class ImpNote {
  String title;
  String body;
  List<String> tags;
  int created; // мс, 0 — неизвестно
  List<String> folder; // цепочка папок от корня
  List<ImpRes> res;
  ImpNote(this.title, this.body,
      {List<String>? tags, this.created = 0, List<String>? folder, List<ImpRes>? res})
      : tags = tags ?? [],
        folder = folder ?? [],
        res = res ?? [];
}

/// Запись промежуточных заметок в хранилище: папки по цепочке, вложения, заметки.
Future<String> commitImport(Store s, List<ImpNote> list,
    {void Function(String)? progress}) async {
  final cache = <String, String>{};
  var fNew = 0, att = 0;

  String folderId(List<String> path) {
    var parent = '';
    var key = '';
    for (final name in path) {
      key = '$key/$name';
      final hit = cache[key];
      if (hit != null) {
        parent = hit;
        continue;
      }
      NoteFolder? f;
      for (final x in s.folders) {
        if (!x.deleted && x.name == name && x.parent == parent) {
          f = x;
          break;
        }
      }
      if (f == null) {
        f = NoteFolder.create(name, parent);
        s.folders.add(f);
        fNew++;
      }
      cache[key] = f.id;
      parent = f.id;
    }
    return parent;
  }

  var k = 0;
  for (final n in list) {
    k++;
    if (k % 20 == 0) {
      progress?.call('Заметки: $k из ${list.length}');
      await Future<void>.delayed(Duration.zero);
    }
    for (final r in n.res) {
      if (!s.hasAttachment(r.id)) {
        await s.writeAttachment(r.id, r.bytes);
        att++;
      }
    }
    final t = nowMs();
    s.notes.add(Note(
      id: newId(),
      title: n.title.isEmpty ? 'Без названия' : n.title,
      vault: 'personal',
      author: s.author,
      authorId: s.profileId,
      editor: s.author,
      createdAt: n.created > 0 ? n.created : t,
      updatedAt: t,
      folder: folderId(n.folder),
      tags: n.tags,
      blocks: [Block(type: 'text', content: n.body)],
    ));
  }
  progress?.call('Сохранение…');
  s.foldersChanged();
  s.changed();
  return 'заметок: ${list.length}, папок: $fNew, вложений: $att';
}
