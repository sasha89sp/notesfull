// ▸ Backup (полный бэкап профиля, страховочные копии safety/), Jex (импорт/экспорт Joplin JEX, экспорт Markdown, bodyOf/bodyLines)
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

part 'backup_2.dart';
part 'backup_3.dart';
part 'backup_4.dart';
part 'backup_5.dart';


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
      if (rel.startsWith('safety/')) continue; // страховочные копии не кладём в бэкап
      files[rel] = await e.readAsBytes();
      count++;
      if (count % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
    AppLog.I.i('backup', 'Бэкап: файлов $count');
    // упаковка в отдельном потоке, чтобы интерфейс не подвисал
    return compute(_zipIso, files);
  }

  // ------------------------------------------------- страховочные копии

  static const int safetyKeep = 5;

  static Directory safetyDir(Store s) =>
      Directory('${s.baseDir.path}${Platform.pathSeparator}safety');

  /// Автоматическая копия во внутреннюю папку перед рискованным действием
  /// (сброс, восстановление, импорт). Хранятся последние [safetyKeep] штук.
  /// Возвращает путь или null, если сделать копию не удалось.
  static Future<String?> safetyCopy(Store s, String reason) async {
    try {
      final bytes = await create(s);
      final d = safetyDir(s);
      await d.create(recursive: true);
      final f = File('${d.path}${Platform.pathSeparator}${_stamp()}_$reason.zip');
      await f.writeAsBytes(bytes, flush: true);
      final all = await listSafety(s);
      for (var i = safetyKeep; i < all.length; i++) {
        try {
          await all[i].delete();
        } catch (_) {}
      }
      AppLog.I.i('backup', 'Страховочная копия ($reason): ${f.path}');
      return f.path;
    } catch (e, stk) {
      AppLog.I.e('backup', 'Страховочная копия не создана: $e', stk);
      return null;
    }
  }

  /// Страховочные копии, новые первыми.
  static Future<List<File>> listSafety(Store s) async {
    final d = safetyDir(s);
    if (!await d.exists()) return [];
    final l = <File>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is File && e.path.endsWith('.zip')) l.add(e);
    }
    l.sort((a, b) => b.path.compareTo(a.path));
    return l;
  }

  /// Человекочитаемая подпись: «14.11.2026 10:15 · перед сбросом».
  static String safetyLabel(File f) {
    final n = f.uri.pathSegments.last.replaceAll('.zip', '');
    final p = n.split('_');
    if (p.length < 3) return n;
    final d = p[0], t = p[1];
    final why = {'reset': 'перед сбросом', 'restore': 'перед восстановлением', 'joplin': 'перед импортом Joplin', 'import': 'перед импортом'}[p[2]] ?? p[2];
    if (d.length != 8 || t.length != 6) return n;
    return '${d.substring(6)}.${d.substring(4, 6)}.${d.substring(0, 4)} ${t.substring(0, 2)}:${t.substring(2, 4)} · $why';
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