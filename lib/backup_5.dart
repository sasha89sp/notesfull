part of 'backup.dart';

class JexIo {


  // ------------------------------------------------------------ экспорт

  static String _tableMd(TableData t) {
    if (t.rows == 0 || t.cols == 0) return '';
    String cell(int r, int c) =>
        t.cells[r][c].v.replaceAll('|', '\\|').replaceAll('\n', ' ');
    final b = StringBuffer();
    b.writeln('| ${List.generate(t.cols, (c) => cell(0, c)).join(' | ')} |');
    b.writeln('| ${List.generate(t.cols, (_) => '---').join(' | ')} |');
    for (var r = 1; r < t.rows; r++) {
      b.writeln('| ${List.generate(t.cols, (c) => cell(r, c)).join(' | ')} |');
    }
    return b.toString().trimRight();
  }

  /// Строки Markdown заметки без вложений (для PDF).
  static List<String> bodyLines(Note n) => bodyOf(n, (b) => null).split('\n');

  /// Блоки заметки → Markdown. [resId] выдаёт ссылку на вложение по id вложения.
  static String bodyOf(Note n, String? Function(Block b) resId,
      {String? Function(String attId)? refId}) {
    final parts = <String>[];
    for (final b in n.blocks) {
      switch (b.type) {
        case 'checklist':
          parts.add(b.items
              .where((i) => i.text.trim().isNotEmpty)
              .map((i) => '- [${i.done ? 'x' : ' '}] ${i.text}')
              .join('\n'));
          break;
        case 'quote':
          parts.add(b.content.split('\n').map((l) => '> $l').join('\n'));
          break;
        case 'code':
          parts.add('```\n${b.content}\n```');
          break;
        case 'table':
          parts.add(_tableMd(b.table));
          break;
        case 'image':
        case 'file':
        case 'voice':
          final id = resId(b);
          final name = (b.meta['name'] ?? (b.type == 'voice' ? 'voice.m4a' : 'файл')).toString();
          if (id != null) {
            parts.add(b.type == 'image' ? '![$name](:/$id)' : '[$name](:/$id)');
          }
          if (b.type == 'voice' && b.content.trim().isNotEmpty) {
            parts.add(b.content.trim());
          }
          break;
        default:
          parts.add(refId == null ? b.content : _rewriteRefs(b.content, refId));
      }
    }
    return parts.where((p) => p.trim().isNotEmpty).join('\n\n');
  }

  /// Ссылки `:/id` на вложения в тексте → идентификаторы ресурсов Joplin.
  static String _rewriteRefs(String text, String? Function(String) refId) {
    return text.replaceAllMapped(RegExp(r':/([A-Za-z0-9]+)'), (m) {
      final r = refId(m.group(1)!);
      return r == null ? m.group(0)! : ':/$r';
    });
  }

  /// Импорт в хранилище. Заметки с уже существующим id пропускаются (повторный импорт
  /// не создаёт дублей). Вся разметка Joplin сохраняется как Markdown-текст, вложения
  /// записываются под их прежними идентификаторами, поэтому ссылки `:/id` остаются рабочими.
  /// Возвращает текст итога.
  static Future<String> importInto(Store s, List<int> tarBytes,
      {void Function(String)? progress}) async {
    progress?.call('Чтение архива…');
    final data = await compute(_parseIso, tarBytes);
    var nNew = 0, nSkip = 0, fNew = 0, att = 0, tasks = 0, nDel = 0;

    final folderIds = <String>{for (final f in s.folders) f.id};
    for (final f in data.folders) {
      if (folderIds.contains(f.id)) continue;
      s.folders.add(NoteFolder(
        id: f.id,
        name: f.title.isEmpty ? 'Папка' : f.title,
        parent: f.parent,
        updatedAt: nowMs(),
      ));
      folderIds.add(f.id);
      fNew++;
    }
    // родитель, которого нет в архиве, превращаем в корень
    for (final f in s.folders) {
      if (f.parent.isNotEmpty && !folderIds.contains(f.parent)) f.parent = '';
    }

    var i = 0;
    final total = data.resources.length;
    for (final r in data.resources.values) {
      final id = r.id.toLowerCase();
      if (!s.hasAttachment(id)) {
        await s.writeAttachment(id, r.bytes);
        att++;
      }
      i++;
      if (i % 5 == 0) progress?.call('Вложения: $i из $total');
      if (i % 20 == 0) await Future<void>.delayed(Duration.zero);
    }

    final known = {for (final n in s.notes) n.id};
    var k = 0;
    for (final jn in data.notes) {
      k++;
      if (k % 25 == 0) {
        progress?.call('Заметки: $k из ${data.notes.length}');
        await Future<void>.delayed(Duration.zero);
      }
      if (jn.deleted) {
        nDel++;
        continue;
      }
      if (known.contains(jn.id)) {
        nSkip++;
        continue;
      }
      var body = jn.markup == 2 ? JexParse.htmlToMd(jn.body) : jn.body;
      body = body.replaceAllMapped(JexParse._idRef, (m) => ':/${m.group(1)!.toLowerCase()}');
      final extra = <String>[];
      if (jn.sourceUrl.isNotEmpty) extra.add('Источник: ${jn.sourceUrl}');
      if (jn.lat != 0 || jn.lon != 0) extra.add('Координаты: ${jn.lat}, ${jn.lon}');
      if (extra.isNotEmpty) body = '$body\n\n---\n${extra.join('  \n')}';

      final tags = [...jn.tags];
      if (jn.isTodo) tags.add(jn.todoDone ? 'выполнено' : 'задача');
      if (jn.conflict) tags.add('конфликт');

      final n = Note(
        id: jn.id,
        title: jn.title,
        vault: 'personal',
        author: s.author,
        authorId: s.profileId,
        editor: s.author,
        createdAt: jn.created,
        updatedAt: nowMs(),
        folder: folderIds.contains(jn.parent) ? jn.parent : '',
        tags: tags,
        blocks: [Block(type: 'text', content: body)],
      );
      s.notes.add(n);
      nNew++;
      if (jn.isTodo && jn.todoDue > 0) {
        s.events.add(CalEvent(
          id: newId(),
          title: jn.title.isEmpty ? 'Задача' : jn.title,
          start: jn.todoDue,
          end: jn.todoDue + const Duration(hours: 1).inMilliseconds,
          isTask: true,
          done: jn.todoDone,
          remind: jn.todoDone ? -1 : 15,
          noteId: jn.id,
          updatedAt: nowMs(),
        ));
        tasks++;
      }
    }
    progress?.call('Сохранение…');
    s.foldersChanged();
    if (tasks > 0) s.eventsChanged();
    s.changed();
    AppLog.I.i('jex',
        'Импорт Joplin: заметок $nNew, папок $fNew, вложений $att, задач $tasks, пропущено $nSkip');
    return 'заметок: $nNew, папок: $fNew, вложений: $att'
        '${tasks > 0 ? ', задач в календаре: $tasks' : ''}'
        '${nSkip > 0 ? ', уже были: $nSkip' : ''}'
        '${nDel > 0 ? ', из корзины Joplin пропущено: $nDel' : ''}';
  }

  /// Заметки в Markdown: папки блокнотов → папки архива, вложения → `_resources/`.
  /// Если заметка одна и без вложений, возвращается просто текст .md (см. [singleMarkdown]).
  static Future<List<int>> exportMarkdown(Store s, List<Note> notes) async {
    final ar = Archive();
    String safe(String x) {
      final t = x.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      return t.isEmpty ? 'Без названия' : t;
    }

    final taken = <String>{};
    final resDone = <String>{};
    for (final n in notes.where((n) => !n.deleted)) {
      final files = <String, String>{}; // id вложения → имя файла в _resources
      String nameFor(String id) {
        var name = '';
        for (final b in n.blocks) {
          if (b.att == id) name = (b.meta['name'] ?? '').toString();
          if (name.isEmpty) {
            final mm = RegExp('!?\\[([^\\]]*)\\]\\(:/${RegExp.escape(id)}').firstMatch(b.content);
            if (mm != null) name = mm.group(1) ?? '';
          }
        }
        final e = Jex._ext(name);
        return e.isEmpty ? id : '$id.$e';
      }

      String? ref(String id) {
        if (!s.hasAttachment(id)) return null;
        return files.putIfAbsent(id, () => nameFor(id));
      }

      var body = bodyOf(n, (b) => b.att == null ? null : ref(b.att!), refId: ref);
      body = body.replaceAllMapped(RegExp(r':/([A-Za-z0-9]+)'), (m) {
        final f = files[m.group(1)!];
        return f == null ? m.group(0)! : '_resources/$f';
      });
      final folder = n.folder.isEmpty ? '' : s.folderPath(n.folder).split(' / ').map(safe).join('/');
      var path = '${folder.isEmpty ? '' : '$folder/'}${safe(n.title)}';
      var k = 1;
      while (!taken.add(path.toLowerCase())) {
        path = '${folder.isEmpty ? '' : '$folder/'}${safe(n.title)} (${++k})';
      }
      final text = utf8.encode('# ${n.title}\n\n$body\n');
      ar.addFile(ArchiveFile('$path.md', text.length, text));
      for (final e in files.entries) {
        if (!resDone.add(e.key)) continue;
        final bytes = await s.readAttachment(e.key);
        if (bytes != null) ar.addFile(ArchiveFile('_resources/${e.value}', bytes.length, bytes));
      }
    }
    return ZipEncoder().encode(ar)!;
  }

  static Future<List<int>> exportFrom(Store s) async {
    final notes = s.notes.where((n) => !n.deleted).toList();
    final att = <String, List<int>>{};
    for (final n in notes) {
      for (final id in n.attachmentIds()) {
        if (att.containsKey(id)) continue;
        final bytes = await s.readAttachment(id);
        if (bytes != null) att[id] = Uint8List.fromList(bytes);
      }
    }
    return Jex.export(s.folders.where((f) => !f.deleted).toList(), notes, att);
  }
}
