// ▸ Часть backup.dart: Backup (полный бэкап профиля, страховочные копии safety/), Jex (импорт/экспорт Joplin JEX, экспорт Markdown, b  [содержит: Jex]
part of 'backup.dart';


/// Формат JEX — tar-архив с файлами «<id>.md» (заметки, папки, теги) и
/// «resources/<id>.<ext>» (вложения).
class Jex {
  static final Random _r = Random.secure();

  static String _hex32() =>
      List.generate(32, (_) => _r.nextInt(16).toRadixString(16)).join();

  static String _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static int _parseTime(String? v) {
    if (v == null || v.isEmpty) return nowMs();
    if (RegExp(r'^\d+$').hasMatch(v)) {
      final n = int.parse(v);
      return n == 0 ? nowMs() : n;
    }
    return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? nowMs();
  }

  /// Срок задачи: 0 и пустое значение — «нет».
  static int _parseDue(String? v) {
    if (v == null || v.isEmpty || v == '0') return 0;
    if (RegExp(r'^\d+$').hasMatch(v)) return int.parse(v);
    return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
  }

  static double _d(String? v) => double.tryParse(v ?? '') ?? 0;

  /// Время: предпочитаем «пользовательское» (user_created_time), как делает Joplin.
  static int _pick(Map<String, String> p, String user, String sys) {
    final u = p[user];
    if (u != null && u.isNotEmpty && u != '0') return _parseTime(u);
    return _parseTime(p[sys]);
  }

  static const Map<String, String> _mimes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'mp3': 'audio/mpeg',
    'txt': 'text/plain',
  };

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  static String _props(Map<String, String> p) =>
      p.entries.map((e) => '${e.key}: ${e.value}').join('\n');

  /// [attBytes]: id вложения → содержимое (вложения, которых нет, пропускаются).
  static List<int> export(
    List<NoteFolder> folders,
    List<Note> notes,
    Map<String, List<int>> attBytes,
  ) {
    final ar = Archive();
    void add(String name, String text) {
      final b = utf8.encode(text);
      ar.addFile(ArchiveFile(name, b.length, b));
    }

    final fid = <String, String>{for (final f in folders) f.id: _hex32()};
    for (final f in folders) {
      add(
        '${fid[f.id]}.md',
        '${f.name}\n\n${_props({
          'id': fid[f.id]!,
          'created_time': _time(f.updatedAt),
          'updated_time': _time(f.updatedAt),
          'user_created_time': _time(f.updatedAt),
          'user_updated_time': _time(f.updatedAt),
          'encryption_cipher_text': '',
          'encryption_applied': '0',
          'parent_id': fid[f.parent] ?? '',
          'is_shared': '0',
          'share_id': '',
          'master_key_id': '',
          'icon': '',
          'type_': '2',
        })}',
      );
    }

    final tagIds = <String, String>{};
    for (final n in notes) {
      final nid = _hex32();
      final resIds = <String, String>{};
      final body = JexIo.bodyOf(n, (b) {
        final att = b.att;
        if (att == null || !attBytes.containsKey(att)) return null;
        return resIds.putIfAbsent(att, () => _hex32());
      }, refId: (id) {
        if (!attBytes.containsKey(id)) return null;
        return resIds.putIfAbsent(id, () => _hex32());
      });

      for (final e in resIds.entries) {
        final bytes = attBytes[e.key]!;
        // имя и тип берём из блока, который ссылается на это вложение
        Block? src;
        for (final b in n.blocks) {
          if (b.att == e.key) src = b;
        }
        var name = (src?.meta['name'] ?? '').toString();
        if (name.isEmpty) {
          // вложение из Markdown-текста: имя берём из ссылки
          for (final b in n.blocks) {
            final mm = RegExp('!?\\[([^\\]]*)\\]\\(:/${RegExp.escape(e.key)}').firstMatch(b.content);
            if (mm != null && (mm.group(1) ?? '').isNotEmpty) {
              name = mm.group(1)!;
              break;
            }
          }
        }
        if (name.isEmpty) name = 'file';
        var ext = _ext(name);
        if (ext.isEmpty && src?.meta['ext'] != null) ext = src!.meta['ext'].toString();
        final mime = _mimes[ext] ?? 'application/octet-stream';
        ar.addFile(ArchiveFile(
            'resources/${e.value}${ext.isEmpty ? '' : '.$ext'}', bytes.length, bytes));
        add(
          '${e.value}.md',
          '$name\n\n${_props({
            'id': e.value,
            'mime': mime,
            'filename': '',
            'created_time': _time(n.createdAt),
            'updated_time': _time(n.updatedAt),
            'user_created_time': _time(n.createdAt),
            'user_updated_time': _time(n.updatedAt),
            'file_extension': ext,
            'encryption_cipher_text': '',
            'encryption_applied': '0',
            'encryption_blob_encrypted': '0',
            'size': '${bytes.length}',
            'is_shared': '0',
            'share_id': '',
            'master_key_id': '',
            'type_': '4',
          })}',
        );
      }

      add(
        '$nid.md',
        '${n.title}\n\n$body\n\n${_props({
          'id': nid,
          'parent_id': fid[n.folder] ?? '',
          'created_time': _time(n.createdAt),
          'updated_time': _time(n.updatedAt),
          'is_conflict': '0',
          'latitude': '0.00000000',
          'longitude': '0.00000000',
          'altitude': '0.0000',
          'author': n.author,
          'source_url': '',
          'is_todo': '0',
          'todo_due': '0',
          'todo_completed': '0',
          'source': 'mysecure-notes',
          'source_application': 'mysecure-notes',
          'application_data': '',
          'order': '0',
          'user_created_time': _time(n.createdAt),
          'user_updated_time': _time(n.updatedAt),
          'encryption_cipher_text': '',
          'encryption_applied': '0',
          'markup_language': '1',
          'is_shared': '0',
          'share_id': '',
          'conflict_original_id': '',
          'master_key_id': '',
          'type_': '1',
        })}',
      );

      for (final t in n.tags) {
        final tid = tagIds.putIfAbsent(t, () {
          final id = _hex32();
          add(
            '$id.md',
            '$t\n\n${_props({
              'id': id,
              'created_time': _time(nowMs()),
              'updated_time': _time(nowMs()),
              'user_created_time': _time(nowMs()),
              'user_updated_time': _time(nowMs()),
              'encryption_cipher_text': '',
              'encryption_applied': '0',
              'is_shared': '0',
              'parent_id': '',
              'type_': '5',
            })}',
          );
          return id;
        });
        final lid = _hex32();
        add(
          '$lid.md',
          _props({
            'id': lid,
            'note_id': nid,
            'tag_id': tid,
            'created_time': _time(nowMs()),
            'updated_time': _time(nowMs()),
            'user_created_time': _time(nowMs()),
            'user_updated_time': _time(nowMs()),
            'encryption_cipher_text': '',
            'encryption_applied': '0',
            'is_shared': '0',
            'type_': '6',
          }),
        );
      }
    }
    return TarEncoder().encode(ar);
  }}