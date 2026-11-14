import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'applog.dart';
import 'models.dart';
import 'gdrive.dart';
import 'remote.dart';
import 'store.dart';
import 'sync.dart';

// =================================================================== бэкап

/// Полный бэкап профиля: zip из зашифрованных файлов (данные остаются под
/// вашим паролем), включая вложения и хранилище паролей.
class Backup {
  static bool _running = false;

  static Future<List<int>> create(Store s) async {
    await s.save();
    final base = s.dir.path;
    final files = <String, Uint8List>{};
    final meta = utf8.encode(jsonEncode({
      'app': 'asrbox',
      'version': 1,
      'created': DateTime.now().toIso8601String(),
      'name': s.author,
    }));
    files['backup.json'] = Uint8List.fromList(meta);
    var count = 0;
    await for (final e in s.dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      var rel = e.path.substring(base.length).replaceAll('\\', '/');
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (rel.endsWith('.tmp') || rel.endsWith('.bak') || rel == 'applog.txt') continue;
      files[rel] = await e.readAsBytes();
      count++;
      if (count % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
    AppLog.I.i('backup', 'Бэкап: файлов $count');
    // упаковка в отдельном потоке, чтобы интерфейс не подвисал
    return compute(_zipIso, files);
  }

  // ---------------------------------------------------------- WebDAV

  /// Куда складывать бэкапы: на текущее хранилище или на отдельный сервер.
  static (Remote, String) target(Store s) {
    final st = s.settings;
    final who = st.userId.isEmpty ? 'profile' : st.userId;
    if (st.bkStorage == 'gdrive') {
      return (GDriveRemote(st), '/ASRbox-Backups/$who');
    }
    if (st.bkStorage == 'custom' && st.bkUrl.isNotEmpty) {
      final f = st.bkFolder.trim().isEmpty ? '/ASRbox-Backups' : st.bkFolder.trim();
      return (Dav(st.bkUrl, st.bkUser, st.bkPass), '${f.startsWith('/') ? f : '/$f'}/$who');
    }
    final r = SyncService.remoteOf(st);
    return (r, '${SyncService.root}/backups/$who');
  }

  static bool canUpload(Settings st) => st.bkStorage == 'gdrive'
      ? st.gClientId.isNotEmpty && st.gdRefresh.isNotEmpty
      : st.bkStorage == 'custom' ? st.bkUrl.isNotEmpty && st.bkUser.isNotEmpty : st.syncConfigured;

  static String _stamp() {
    final d = DateTime.now();
    String t(int x) => x.toString().padLeft(2, '0');
    return '${d.year}${t(d.month)}${t(d.day)}_${t(d.hour)}${t(d.minute)}${t(d.second)}';
  }

  /// Загрузка готового бэкапа на сервер; старые копии сверх лимита удаляются.
  /// Возвращает имя файла.
  static Future<String> upload(Store s, List<int> bytes) async {
    final st = s.settings;
    if (!canUpload(st)) throw 'Не настроен сервер для бэкапов';
    final (r, dir) = target(s);
    await r.mkcolAll(dir);
    final name = 'asrbox_${_stamp()}.zip';
    await r.putAtomic('$dir/$name', bytes);
    st.bkLast = nowMs();
    await s.saveSettings(touch: false);
    final keep = st.bkKeep < 1 ? 1 : st.bkKeep;
    try {
      final names = (await r.list(dir)).where((n) => n.startsWith('asrbox_') && n.endsWith('.zip')).toList()
        ..sort();
      for (final n in names.take(names.length > keep ? names.length - keep : 0)) {
        await r.delete('$dir/$n');
      }
    } catch (e) {
      AppLog.I.w('backup', 'Очистка старых копий: $e');
    }
    AppLog.I.i('backup', 'Бэкап загружен: $name (${bytes.length} байт)');
    return name;
  }

  /// Загрузка отдельного файла (экспорт данных телефона) в папку phone рядом с бэкапами.
  static Future<void> uploadPhone(Store s, String name, List<int> bytes) async {
    if (!canUpload(s.settings)) throw 'Не настроен сервер для бэкапов';
    final (r, dir) = target(s);
    await r.mkcolAll('$dir/phone');
    await r.putAtomic('$dir/phone/$name', bytes);
  }

  /// Создать и сразу загрузить (без сохранения файла на устройство).
  static Future<String> createAndUpload(Store s) async => upload(s, await create(s));

  static Future<List<String>> listRemote(Store s) async {
    final (r, dir) = target(s);
    final l = (await r.list(dir)).where((n) => n.endsWith('.zip')).toList()..sort();
    return l.reversed.toList();
  }

  static Future<List<int>?> downloadRemote(Store s, String name) async {
    final (r, dir) = target(s);
    return r.get('$dir/$name');
  }

  /// Раз в сутки делает бэкап и загружает его, если включено «автоматически».
  static Future<void> autoIfDue(Store s) async {
    final st = s.settings;
    if (_running || !st.bkAuto || !st.bkDaily || s.key == null || !canUpload(st)) return;
    if (nowMs() - st.bkLast < const Duration(hours: 24).inMilliseconds) return;
    _running = true;
    try {
      await createAndUpload(s);
    } catch (e) {
      AppLog.I.e('backup', 'Автобэкап не удался: $e');
    } finally {
      _running = false;
    }
  }

  static bool isBackup(List<int> bytes) {
    try {
      final ar = ZipDecoder().decodeBytes(bytes);
      return ar.files.any((f) => f.name == 'vault.json');
    } catch (_) {
      return false;
    }
  }

  /// Восстановление заменяет данные текущего профиля. После него нужно войти заново
  /// с паролем, под которым был сделан бэкап.
  static Future<int> restore(Store s, List<int> bytes) async {
    final ar = ZipDecoder().decodeBytes(bytes);
    if (!ar.files.any((f) => f.name == 'vault.json')) {
      throw 'Это не бэкап приложения (нет vault.json)';
    }
    // старые данные профиля удаляем, чтобы не смешивать разные состояния
    await for (final e in s.dir.list(followLinks: false)) {
      if (e is File) {
        final n = e.uri.pathSegments.last;
        if (n.endsWith('.enc') || n == 'vault.json' || n == 'passvault.json') {
          await e.delete();
        }
      } else if (e is Directory && e.uri.pathSegments.contains('attachments')) {
        await e.delete(recursive: true);
      }
    }
    var count = 0;
    for (final f in ar.files) {
      if (!f.isFile || f.name == 'backup.json') continue;
      if (f.name.contains('..')) continue;
      final out = File('${s.dir.path}${Platform.pathSeparator}${f.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
      count++;
    }
    AppLog.I.i('backup', 'Восстановлено файлов: $count');
    return count;
  }
}

// =================================================================== Joplin (JEX)

class JexResource {
  String id;
  String name;
  String mime;
  List<int> bytes;
  JexResource(this.id, this.name, this.mime, this.bytes);
}

class JexFolder {
  String id, title, parent;
  JexFolder(this.id, this.title, this.parent);
}

class JexNote {
  String id, title, body, parent;
  int created, updated;
  List<String> tags;
  bool isTodo;
  int todoDue; // мс, 0 — нет срока
  bool todoDone;
  int markup; // 1 — Markdown, 2 — HTML
  String sourceUrl;
  double lat, lon;
  bool deleted;
  bool conflict;
  JexNote(this.id, this.title, this.body, this.parent, this.created,
      this.updated, this.tags,
      {this.isTodo = false,
      this.todoDue = 0,
      this.todoDone = false,
      this.markup = 1,
      this.sourceUrl = '',
      this.lat = 0,
      this.lon = 0,
      this.deleted = false,
      this.conflict = false});
}

class JexParsed {
  final List<JexFolder> folders = [];
  final List<JexNote> notes = [];
  final Map<String, JexResource> resources = {};
  int skipped = 0;
}

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
      final body = bodyOf(n, (b) {
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
  }

  // ------------------------------------------------------------ импорт

  /// Разбор «заголовок + тело + свойства». Свойства — блок «ключ: значение» в конце.
  static (String, String, Map<String, String>) splitItem(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var i = lines.length - 1;
    while (i >= 0 && lines[i].trim().isEmpty) {
      i--;
    }
    final props = <String, String>{};
    final re = RegExp(r'^([A-Za-z_]+): ?(.*)$');
    while (i >= 0 && lines[i].trim().isNotEmpty) {
      final m = re.firstMatch(lines[i]);
      if (m == null) break;
      props[m.group(1)!] = m.group(2)!;
      i--;
    }
    // оставшееся: заголовок, пустая строка, тело
    final rest = lines.sublist(0, i < 0 ? 0 : i + 1);
    var title = '';
    var body = '';
    if (props.containsKey('type_') && props['type_'] == '6') {
      return ('', '', props);
    }
    if (rest.isNotEmpty) {
      title = rest.first;
      var from = 1;
      if (from < rest.length && rest[from].trim().isEmpty) from++;
      body = rest.sublist(from < rest.length ? from : rest.length).join('\n').trim();
    }
    return (title, body, props);
  }

  static JexParsed parse(List<int> tarBytes) {
    final res = JexParsed();
    final ar = TarDecoder().decodeBytes(tarBytes);
    final resMeta = <String, Map<String, String>>{};
    final resFiles = <String, List<int>>{};
    final tags = <String, String>{}; // id → название
    final links = <String, List<String>>{}; // note → tag ids

    for (final f in ar.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      final content = f.content as List<int>;
      if (name.startsWith('resources/')) {
        final base = name.substring('resources/'.length);
        final dot = base.indexOf('.');
        resFiles[dot < 0 ? base : base.substring(0, dot)] = content;
        continue;
      }
      if (!name.endsWith('.md')) continue;
      final (title, body, p) = splitItem(utf8.decode(content, allowMalformed: true));
      final type = p['type_'] ?? '';
      final id = p['id'] ?? name.substring(0, name.length - 3);
      switch (type) {
        case '1':
          res.notes.add(JexNote(
            id,
            title,
            body,
            p['parent_id'] ?? '',
            _pick(p, 'user_created_time', 'created_time'),
            _pick(p, 'user_updated_time', 'updated_time'),
            [],
            isTodo: p['is_todo'] == '1',
            todoDue: _parseDue(p['todo_due']),
            todoDone: _parseDue(p['todo_completed']) > 0,
            markup: int.tryParse(p['markup_language'] ?? '1') ?? 1,
            sourceUrl: p['source_url'] ?? '',
            lat: _d(p['latitude']),
            lon: _d(p['longitude']),
            deleted: _parseDue(p['deleted_time']) > 0,
            conflict: p['is_conflict'] == '1',
          ));
          break;
        case '2':
          res.folders.add(JexFolder(id, title, p['parent_id'] ?? ''));
          break;
        case '4':
          resMeta[id] = {...p, 'title': title};
          break;
        case '5':
          tags[id] = title;
          break;
        case '6':
          links.putIfAbsent(p['note_id'] ?? '', () => []).add(p['tag_id'] ?? '');
          break;
        default:
          res.skipped++;
      }
    }
    for (final n in res.notes) {
      for (final tid in links[n.id] ?? const <String>[]) {
        final t = tags[tid];
        if (t != null && t.isNotEmpty) n.tags.add(t);
      }
    }
    for (final e in resFiles.entries) {
      final m = resMeta[e.key];
      final name = m == null
          ? e.key
          : ((m['title'] ?? '').isNotEmpty ? m['title']! : (m['filename'] ?? e.key));
      res.resources[e.key] =
          JexResource(e.key, name, m?['mime'] ?? 'application/octet-stream', e.value);
    }
    return res;
  }

  static final RegExp _ref = RegExp(r'!?\[([^\]]*)\]\(:/([0-9a-fA-F]{32})[^)]*\)');
  static final RegExp _check = RegExp(r'^\s*[-*]\s+\[( |x|X)\]\s?(.*)$');

  /// Markdown → блоки. [att] превращает вложение Joplin в блок (или null, если файла нет).
  static List<Block> toBlocks(String body, Block? Function(String resId) att) {
    final blocks = <Block>[];
    final text = <String>[];
    final items = <CheckItem>[];

    void flushText() {
      final t = text.join('\n').trim();
      if (t.isNotEmpty) blocks.add(Block(type: 'text', content: t));
      text.clear();
    }

    void flushItems() {
      if (items.isNotEmpty) {
        blocks.add(Block(type: 'checklist', items: List.of(items)));
      }
      items.clear();
    }

    for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
      final c = _check.firstMatch(line);
      if (c != null) {
        flushText();
        items.add(CheckItem(c.group(2) ?? '', c.group(1) != ' '));
        continue;
      }
      flushItems();
      if (_ref.hasMatch(line)) {
        flushText();
        for (final m in _ref.allMatches(line)) {
          final b = att(m.group(2)!.toLowerCase());
          if (b != null) blocks.add(b);
        }
        final rest = line.replaceAll(_ref, '').trim();
        if (rest.isNotEmpty) text.add(rest);
      } else {
        text.add(line);
      }
    }
    flushItems();
    flushText();
    if (blocks.isEmpty) blocks.add(Block(type: 'text'));
    return blocks;
  }

  /// HTML-заметки Joplin (markup_language = 2) → Markdown, чтобы форматирование сохранилось.
  static String htmlToMd(String html) {
    var s = html.replaceAll('\r\n', '\n');
    String tag(String name, String open, [String? close]) {
      return s.replaceAllMapped(
          RegExp('<$name(?:\\s[^>]*)?>(.*?)</$name>', caseSensitive: false, dotAll: true),
          (m) => '$open${m.group(1)}${close ?? open}');
    }

    s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    s = s.replaceAllMapped(
        RegExp(r'<img\b[^>]*?src="([^"]*)"[^>]*?(?:alt="([^"]*)")?[^>]*>', caseSensitive: false),
        (m) => '![${m.group(2) ?? ''}](${m.group(1)})');
    s = s.replaceAllMapped(
        RegExp(r'<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true),
        (m) => '[${m.group(2)}](${m.group(1)})');
    for (var i = 1; i <= 6; i++) {
      s = s.replaceAllMapped(
          RegExp('<h$i(?:\\s[^>]*)?>(.*?)</h$i>', caseSensitive: false, dotAll: true),
          (m) => '\n\n${'#' * i} ${m.group(1)}\n\n');
    }
    s = tag('strong', '**');
    s = tag('b', '**');
    s = tag('em', '*');
    s = tag('i', '*');
    s = tag('del', '~~');
    s = tag('s', '~~');
    s = tag('u', '++');
    s = tag('mark', '==');
    s = tag('code', '`');
    s = s.replaceAllMapped(
        RegExp(r'<pre(?:\s[^>]*)?>(.*?)</pre>', caseSensitive: false, dotAll: true),
        (m) => '\n```\n${m.group(1)!.replaceAll(RegExp(r'</?code[^>]*>'), '')}\n```\n');
    s = s.replaceAllMapped(
        RegExp(r'<li(?:\s[^>]*)?>(.*?)</li>', caseSensitive: false, dotAll: true),
        (m) => '\n- ${m.group(1)!.trim()}');
    s = s.replaceAllMapped(
        RegExp(r'<blockquote(?:\s[^>]*)?>(.*?)</blockquote>', caseSensitive: false, dotAll: true),
        (m) => '\n${m.group(1)!.trim().split('\n').map((l) => '> $l').join('\n')}\n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n\n---\n\n');
    s = s.replaceAll(RegExp(r'</(p|div|ul|ol|table|tr)>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' | ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static final RegExp _idRef = RegExp(r':/([0-9a-fA-F]{32})');

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
      var body = jn.markup == 2 ? htmlToMd(jn.body) : jn.body;
      body = body.replaceAllMapped(_idRef, (m) => ':/${m.group(1)!.toLowerCase()}');
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
        final e = _ext(name);
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
    return export(s.folders.where((f) => !f.deleted).toList(), notes, att);
  }
}

JexParsed _parseIso(List<int> bytes) => Jex.parse(bytes);

List<int> _zipIso(Map<String, Uint8List> files) {
  final ar = Archive();
  files.forEach((name, bytes) => ar.addFile(ArchiveFile(name, bytes.length, bytes)));
  return ZipEncoder().encode(ar)!;
}
