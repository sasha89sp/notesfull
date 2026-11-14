import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'accounts.dart';
import 'crypto.dart';
import 'gdrive.dart';
import 'groups.dart';
import 'merge.dart';
import 'models.dart';
import 'pass_store.dart';
import 'remote.dart';
import 'store.dart';
import 'util.dart';
import 'synchist.dart';

class SyncService {
  /// Корневая папка данных на хранилище (задаётся при подключении).
  static String root = '/MySecureApp';

  /// Личная папка пользователя: у каждого аккаунта своя, чужие данные недоступны
  /// (и зашифрованы ключом из его собственного пароля).
  static String userId = '';
  static String get personalDir =>
      userId.isEmpty ? '$root/personal' : '$root/users/$userId';

  /// Привязать константы к настройкам текущего профиля.
  static void bind(Settings st) {
    final f = st.folder.trim();
    root = f.isEmpty ? '/MySecureApp' : (f.startsWith('/') ? f : '/$f');
    userId = st.userId;
  }

  /// Хранилище по настройкам: WebDAV или локальная папка.
  static Remote remoteOf(Settings st) {
    bind(st);
    if (st.storage == 'local') return LocalRemote(st.localPath);
    if (st.storage == 'gdrive') return GDriveRemote(st);
    return Dav(st.url, st.user, st.pass);
  }

  static Future<void> run(Store s, SyncStats r, CancelToken tok) async {
    final st = s.settings;
    final dav = remoteOf(st);
    await dav.mkcolAll(root);
    await dav.mkcol('$root/users');
    await dav.mkcol(personalDir);
    await _settingsSync(dav, s);
    tok.check();
    tok.check();

    // 1. Заметки (высокий приоритет)
    await _scope(dav, s, 'personal', personalDir, s.syncKey!, null, r, tok);
    tok.check();

    // 2. События календаря (личные)
    await _mergeBlob(
      dav,
      '$personalDir/events.enc',
      s.syncKey!,
      s.events.map((e) => e.toJson()).toList(),
      (list) {
        s.events = list.map(CalEvent.fromJson).toList();
      },
      r,
      'events',
    );
    tok.check();

    // 2б. Папки заметок
    await _mergeBlob(
      dav,
      '$personalDir/folders.enc',
      s.syncKey!,
      s.folders.map((e) => e.toJson()).toList(),
      (list) {
        s.folders = list.map(NoteFolder.fromJson).toList();
      },
      r,
      'folders',
    );
    tok.check();

    // 2в. Общие папки: у каждой свой WebDAV и ключ; сбой одной не мешает остальным
    for (final g in List<Group>.of(st.groups)) {
      tok.check();
      if (g.removed || g.key.isEmpty) continue;
      try {
        await _group(s, g, r, tok);
      } on SyncCancelled {
        rethrow;
      } catch (e) {
        r.log.add('Общая папка «${g.name}»: $e');
      }
    }
    tok.check();

    // 3. Вложения (низкий приоритет)
    await _attachments(dav, s, r, tok);
  }

  /// Внутренние настройки (календарь, ключи, модули…) едут вместе с аккаунтом:
  /// побеждает версия с более поздней отметкой времени.
  static Future<void> _settingsSync(Remote dav, Store s) async {
    final k = s.syncKey;
    if (k == null) return;
    final st = s.settings;
    final m = await Accounts.pullSettings(dav, personalDir, k);
    final ru = (m?['settingsUpdatedAt'] ?? 0) as int;
    if (m != null && ru > st.settingsUpdatedAt) {
      s.settings = Accounts.applySettings(st, m);
      await s.saveSettings(touch: false);
      bind(s.settings);
    } else if (m == null || st.settingsUpdatedAt > ru) {
      await Accounts.pushSettings(dav, personalDir, k, st);
    }
  }

  /// Проверка при подключении онлайн-профиля: есть ли в облаке данные и подходит ли пароль.
  /// Возвращает ok | empty | wrong | error:<текст>
  static Future<String> verifyJoin(
      String url, String user, String pass, String pw) async {
    try {
      final dav = Dav(url, user, pass);
      final sk = await Crypto.deriveFixed(pw, 'mysecure-personal-sync-v1');
      Future<String?> tryDecrypt(Uint8List? b) async {
        if (b == null) return null;
        try {
          await Crypto.decrypt(sk, b);
          return 'ok';
        } catch (_) {
          return 'wrong';
        }
      }

      final ev = await tryDecrypt(await dav.get('$personalDir/events.enc'));
      if (ev != null) return ev;
      final mb = await dav.get('$personalDir/manifest.json');
      if (mb != null) {
        final m = jsonDecode(utf8.decode(mb)) as Map<String, dynamic>;
        if (m.isNotEmpty) {
          final r = await tryDecrypt(await dav.get('$personalDir/${m.keys.first}.enc'));
          if (r != null) return r;
        }
      }
      return 'empty';
    } catch (e) {
      return 'error:$e';
    }
  }

  /// Проверка пароля для данных старой версии (папка с `personal` без аккаунтов).
  /// Возвращает ok | empty | wrong | error:<текст>
  static Future<String> verifyLegacy(Remote r, String folder, String pw) async {
    try {
      final sk = await Crypto.deriveFixed(pw, 'mysecure-personal-sync-v1');
      final dir = '${folder.startsWith('/') ? folder : '/$folder'}/personal';
      final ev = await r.get('$dir/events.enc');
      if (ev != null) {
        try {
          await Crypto.decrypt(sk, ev);
          return 'ok';
        } catch (_) {
          return 'wrong';
        }
      }
      return 'empty';
    } catch (e) {
      return 'error:$e';
    }
  }

  // ---------------------------------------------------------------- профиль

  /// Синхронизация одной общей папки: права, участники, заметки, комментарии, чат.
  static Future<void> _group(Store s, Group g, SyncStats r, CancelToken tok) async {
    final dav = Groups.remoteOf(g);
    final key = Groups.keyOf(g);
    await dav.mkcolAll(g.folder);
    await dav.mkcol(g.profilesDir);
    await Groups.applyAcl(dav, g, s);
    if (g.removed) {
      r.log.add('Вас удалили из общей папки «${g.name}»');
      await s.saveSettings(touch: false);
      return;
    }
    await Groups.putProfile(dav, g, s);
    await _scope(dav, s, g.vault, g.notesDir, key, g, r, tok);
    tok.check();
    await _comments(dav, s, g, key, r, tok);
    await _chat(dav, s, g, key, r, tok);
  }

  // ---------------------------------------------------------------- заметки

  static Future<void> _scope(Remote dav, Store s, String vault, String dir,
      SecretKey key, Group? grp, SyncStats r, CancelToken tok) async {
    final kind = vault == 'personal' ? 'notes' : 'family';
    await dav.mkcol(dir);

    final manifest = <String, int>{};
    final mb = await dav.get('$dir/manifest.json');
    if (mb != null) {
      final m = jsonDecode(utf8.decode(mb)) as Map<String, dynamic>;
      m.forEach((k, v) => manifest[k] = (v as num).toInt());
    }
    var changed = false;
    try {

    // Корзина: заметки, удалённые более 30 дней назад, стираются и на сервере
    final purgeBefore = nowMs() - kTrashDays * 24 * 3600 * 1000;
    for (final n in List<Note>.of(s.notes)) {
      if (n.vault == vault && n.deleted && n.updatedAt < purgeBefore && (n.syncedAt >= n.updatedAt || n.syncedAt == 0)) {
        await dav.delete('$dir/${n.id}.enc');
        manifest.remove(n.id);
        s.notes.remove(n);
        changed = true;
      }
    }

    // скачиваем изменённое на сервере: запросы идут параллельно, применение — по очереди
    final todo = <MapEntry<String, int>>[];
    for (final e in manifest.entries) {
      final local = s.byId(e.key);
      if (local != null && local.vault != vault) continue;
      if (local != null && e.value <= local.syncedAt) continue;
      todo.add(e);
    }
    final fetched = <String, Note>{};
    await runPool([
      for (final e in todo)
        () async {
          tok.check();
          final bytes = await dav.get('$dir/${e.key}.enc');
          if (bytes == null) return;
          final obj = await Crypto.decryptJson(key, bytes);
          fetched[e.key] = Note.fromJson(Map<String, dynamic>.from(obj as Map));
        }
    ]);
    for (final e in todo) {
      tok.check();
      final remote = fetched[e.key];
      if (remote == null) continue;
      final local = s.byId(e.key);
      remote.vault = vault;
      if (grp != null && remote.authorId != s.settings.profileId && remote.editor != (grp.myName.isEmpty ? s.author : grp.myName) &&
          (local != null || s.notes.any((x) => x.vault == vault))) {
        s.notices.putIfAbsent(grp.name.isEmpty ? 'Общая папка' : grp.name, () => [0, 0])[1]++;
      }

      if (local == null) {
        remote.syncedAt = remote.updatedAt;
        remote.markSynced();
        s.notes.add(remote);
        r.d(kind);
      } else if (local.updatedAt > local.syncedAt) {
        // Изменено и там, и тут: пробуем слить по блокам / строкам / ячейкам
        final merged = mergeNotes(local, remote);
        if (merged != null) {
          final idx = s.notes.indexOf(local);
          if (idx >= 0) s.notes[idx] = merged;
          r.d(kind);
        } else {
          // правки пересеклись: серверную версию сохраняем копией
          remote.id = newId();
          remote.title = '${remote.title} (конфликт)';
          remote.syncedAt = 0;
          s.notes.add(remote);
          r.conflicts++;
          r.log.add('Конфликт: «${remote.title}» сохранена копией');
        }
      } else {
        final idx = s.notes.indexOf(local);
        remote.history = local.history;
        remote.syncedAt = remote.updatedAt;
        remote.markSynced();
        if (idx >= 0) s.notes[idx] = remote;
        r.d(kind);
      }
    }

    // загружаем локальные изменения параллельно
    final toUp = <Note>[];
    for (final n in List<Note>.of(s.notes)) {
      if (n.vault != vault) continue;
      if (grp != null && !grp.canEditNote(n, s.settings.profileId)) continue; // права участника
      final inManifest = manifest.containsKey(n.id);
      if (inManifest && n.updatedAt <= n.syncedAt) continue;
      toUp.add(n);
    }
    await runPool([
      for (final n in toUp)
        () async {
          tok.check();
          final stamp = n.updatedAt;
          final data = await Crypto.encryptJson(key, n.toJson(withHistory: false));
          await dav.putAtomic('$dir/${n.id}.enc', data);
          manifest[n.id] = stamp;
          n.syncedAt = stamp;
          n.markSynced();
          r.u(kind);
          changed = true;
        }
    ]);

    } finally {
      // манифест записываем и при отмене: уже загруженное не уйдёт повторно
      if (changed) {
        await dav.putAtomic(
            '$dir/manifest.json', utf8.encode(jsonEncode(manifest)));
      }
    }
  }

  // ---------------------------------------------------------------- слияние коллекций

  /// Слияние списка записей {id, updatedAt} по принципу «новее побеждает».
  static Future<void> _mergeBlob(
    Remote dav,
    String path,
    SecretKey key,
    List<Map<String, dynamic>> local,
    void Function(List<Map<String, dynamic>>) apply,
    SyncStats r,
    String kind,
  ) async {
    final bytes = await dav.get(path);
    final remote = <Map<String, dynamic>>[];
    if (bytes != null) {
      final clear = await Crypto.decrypt(key, bytes);
      for (final e in jsonDecode(utf8.decode(clear)) as List) {
        remote.add(Map<String, dynamic>.from(e as Map));
      }
    }
    final rm = {for (final e in remote) e['id'] as String: e};
    final lm = {for (final e in local) e['id'] as String: e};
    final merged = <String, Map<String, dynamic>>{};
    var localChanged = false;
    var remoteChanged = false;
    var nUp = 0, nDown = 0;

    for (final e in remote) {
      merged[e['id'] as String] = e;
    }
    for (final e in local) {
      final id = e['id'] as String;
      final re = rm[id];
      if (re == null) {
        merged[id] = e;
        remoteChanged = true;
        nUp++;
      } else {
        final lu = (e['updatedAt'] as num).toInt();
        final ru = (re['updatedAt'] as num).toInt();
        if (lu > ru) {
          merged[id] = e;
          remoteChanged = true;
          nUp++;
        } else if (ru > lu) {
          localChanged = true;
          nDown++;
        }
      }
    }
    for (final id in rm.keys) {
      if (!lm.containsKey(id)) {
        localChanged = true;
        nDown++;
      }
    }

    final list = merged.values.toList();
    if (localChanged) {
      apply(list);
      r.d(kind, nDown);
    }
    if (remoteChanged) {
      await dav.putAtomic(
          path, await Crypto.encrypt(key, utf8.encode(jsonEncode(list))));
      r.u(kind, nUp);
    }
  }

  /// Менеджер паролей (вызывается отдельно, когда хранилище паролей открыто)
  static Future<void> runPasswords(Store s, PassStore p) async {
    final st = s.settings;
    if (!st.syncConfigured || !p.unlocked || p.syncKey == null) return;
    final dav = remoteOf(st);
    await dav.mkcolAll(root);
    await dav.mkcol('$root/users');
    await dav.mkcol(personalDir);
    final r = SyncStats();
    await _mergeBlob(
      dav,
      '$personalDir/passwords.enc',
      p.syncKey!,
      p.entries.map((e) => e.toJson()).toList(),
      (list) {
        p.entries = list.map(PassEntry.fromJson).toList();
      },
      r,
      'passwords',
    );
    await s.addHistory(SyncRecord(
      at: nowMs(),
      status: 'ok',
      targets: ['WebDAV (пароли)'],
      up: r.up,
      down: r.down,
      log: r.log,
    ));
  }

  // ---------------------------------------------------------------- комментарии

  static final Map<String, int> _cSeen = {};
  static final Map<String, int> _cFull = {};

  static Future<void> _comments(
      Remote dav, Store s, Group g, SecretKey fk, SyncStats r, CancelToken tok) async {
    final famNotes =
        s.notes.where((n) => n.vault == g.vault && !n.deleted).toList();
    if (famNotes.isEmpty) return;
    final familyDir = g.notesDir;
    await dav.mkcol('$familyDir/comments');
    // индекс комментариев: один файл вместо опроса папки каждой заметки.
    // Полная проверка — раз в 6 часов и при первом запуске, чтобы не потерять гонки записи индекса.
    final idx = <String, int>{};
    try {
      final ib = await dav.get('$familyDir/comments/_idx.json');
      if (ib != null) {
        (jsonDecode(utf8.decode(ib)) as Map).forEach((k, v) => idx[k.toString()] = (v as num).toInt());
      }
    } catch (_) {}
    final full = nowMs() - (_cFull[g.id] ?? 0) > 6 * 3600 * 1000;
    final touched = <String, int>{};

    await runPool([
      for (final n in famNotes)
        () async {
      tok.check();
      final d = '$familyDir/comments/${n.id}';
      final ck = '${g.id}:${n.id}';
      final ts = idx[n.id] ?? 0;
      final mine = s.comments.where((c) => c.noteId == n.id).toList();
      final hasUnsynced =
          mine.any((c) => !c.synced || (c.deleted && !c.delSynced));
      if (!full && !hasUnsynced && _cSeen.containsKey(ck) && ts <= _cSeen[ck]!) return;
      final names = await dav.list(d);
      _cSeen[ck] = ts;
      if (names.isEmpty && !hasUnsynced) return;
      if (hasUnsynced) touched[n.id] = nowMs();
      if (hasUnsynced) await dav.mkcol(d);

      final delMarks = names
          .where((x) => x.endsWith('.del.enc'))
          .map((x) => '${x.substring(0, x.length - '.del.enc'.length)}.enc')
          .toSet();

      for (final name
          in names.where((x) => x.endsWith('.enc') && !x.endsWith('.del.enc'))) {
        Comment? known;
        for (final c in s.comments) {
          if (c.file == name) known = c;
        }
        if (known == null) {
          final bytes = await dav.get('$d/$name');
          if (bytes == null) continue;
          final clear = await Crypto.decrypt(fk, bytes);
          final c = Comment.fromJson(
              jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
          c.file = name;
          c.synced = true;
          if (delMarks.contains(name)) {
            c.deleted = true;
            c.text = '';
            c.delSynced = true;
          }
          s.comments.add(c);
          r.d('comments');
        } else if (delMarks.contains(name)) {
          known.deleted = true;
          known.text = '';
          known.delSynced = true;
        }
      }

      for (final c in s.comments.where((c) => c.noteId == n.id).toList()) {
        if (!c.synced && c.file.isNotEmpty) {
          await dav.put('$d/${c.file}',
              await Crypto.encrypt(fk, utf8.encode(jsonEncode(c.toJson()))));
          c.synced = true;
          r.u('comments');
        }
        if (c.deleted && !c.delSynced && c.file.isNotEmpty) {
          final base = c.file.substring(0, c.file.length - '.enc'.length);
          await dav.put('$d/$base.del.enc',
              await Crypto.encrypt(fk, utf8.encode('deleted')));
          c.delSynced = true;
          r.u('comments');
        }
      }
        }
    ]);
    if (full) _cFull[g.id] = nowMs();
    if (touched.isNotEmpty) {
      // обновляем индекс: берём свежую версию и поднимаем отметки времени
      try {
        final cur = <String, int>{};
        final ib = await dav.get('$familyDir/comments/_idx.json');
        if (ib != null) {
          (jsonDecode(utf8.decode(ib)) as Map).forEach((k, v) => cur[k.toString()] = (v as num).toInt());
        }
        touched.forEach((k, v) {
          if ((cur[k] ?? 0) < v) cur[k] = v;
        });
        await dav.putAtomic('$familyDir/comments/_idx.json', utf8.encode(jsonEncode(cur)));
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- вложения

  static Future<bool> _onWifi() async {
    try {
      final res = await Connectivity().checkConnectivity();
      return res.contains(ConnectivityResult.wifi) ||
          res.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  }

  /// Чат группы: каждое сообщение — отдельный файл, зашифрованный ключом группы.
  static Future<void> _chat(
      Remote g, Store s, Group grp, SecretKey fk, SyncStats r, CancelToken tok) async {
    await s.ensureChat();
    final room = grp.id;
    final dir = '${grp.chatDir}/$room';
    var changed = false;
    final unsent = s.chat.where((m) => m.room == room && !m.synced).toList();
    if (unsent.isNotEmpty && !grp.viewOnly) {
      await g.mkcolAll(dir);
      for (final m in unsent) {
        tok.check();
        await g.putAtomic('$dir/${m.fileName}',
            await Crypto.encrypt(fk, utf8.encode(jsonEncode(m.toWire()))));
        m.synced = true;
        changed = true;
        r.u('chat');
      }
    }
    final names = (await g.list(dir)).where((n) => n.endsWith('.enc')).toList()..sort();
    final have = s.chat.where((m) => m.room == room).map((m) => m.id).toSet();
    for (final n in names.reversed.take(300)) {
      tok.check();
      final id = n.substring(0, n.length - 4).split('_').last;
      if (have.contains(id)) continue;
      final b = await g.get('$dir/$n');
      if (b == null) continue;
      try {
        final m = ChatMsg.fromJson(Map<String, dynamic>.from(
            jsonDecode(utf8.decode(await Crypto.decrypt(fk, b))) as Map));
        m.room = room;
        m.synced = true;
        if (have.isNotEmpty && m.authorId != s.settings.profileId) {
          s.notices.putIfAbsent(grp.name.isEmpty ? 'Общая папка' : grp.name, () => [0, 0])[0]++;
        }
        s.chat.add(m);
        changed = true;
        r.d('chat');
      } catch (_) {
        // повреждённый файл — пропускаем
      }
    }
    if (changed) {
      s.chat.sort((a, b) => a.at.compareTo(b.at));
      await s.saveChat();
      s.refresh();
    }
  }

  /// Лёгкое обновление только чата одной группы (опрос из экрана чата).
  static Future<void> chatOnly(Store s, Group g) async {
    if (g.removed || g.key.isEmpty) return;
    await _chat(Groups.remoteOf(g), s, g, Groups.keyOf(g), SyncStats(), CancelToken());
  }

  static Future<void> _attachments(
      Remote dav, Store s, SyncStats r, CancelToken tok) async {
    final mode = s.settings.attMode;
    if (mode == 'off') return;
    if (mode == 'wifi' && !await _onWifi()) return;

    final done = s.settings.attDone;
    final noteIds = {for (final x in s.notes) x.id};
    final jobs = <Future<void> Function()>[];
    for (final n in List<Note>.of(s.notes)) {
      tok.check();
      if (n.deleted) continue;
      Remote rm = dav;
      SecretKey? key = s.syncKey;
      var dir = '$personalDir/attachments';
      if (n.isGroup) {
        final g = Groups.byVault(s.settings, n.vault);
        if (g == null || g.removed || g.key.isEmpty) continue;
        rm = Groups.remoteOf(g);
        key = Groups.keyOf(g);
        dir = '${g.notesDir}/attachments';
      }
      if (key == null) continue;
      final k = key;
      final rem = rm;
      final adir = dir;
      var dirMade = false;

      for (final id in n.attachmentIds()) {
        if (noteIds.contains(id)) continue; // ссылка на заметку, а не на файл
        final tag = '${n.vault}:$id';
        if (s.hasAttachment(id)) {
          if (done.contains(tag)) continue;
          if (!dirMade) {
            await rem.mkcol(adir);
            dirMade = true;
          }
          jobs.add(() async {
            tok.check();
            final plain = await s.readAttachment(id);
            if (plain == null) return;
            await rem.putAtomic('$adir/$id.enc', await Crypto.encrypt(k, plain));
            done.add(tag);
            r.u('attachments');
          });
        } else {
          jobs.add(() async {
            tok.check();
            final bytes = await rem.get('$adir/$id.enc');
            if (bytes == null) return;
            final plain = await Crypto.decrypt(k, bytes);
            await s.writeAttachment(id, plain);
            done.add(tag);
            r.d('attachments');
          });
        }
      }
    }
    await runPool(jobs, limit: 4);
  }
}
