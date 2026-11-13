import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'accounts.dart';
import 'crypto.dart';
import 'family.dart';
import 'merge.dart';
import 'models.dart';
import 'pass_store.dart';
import 'remote.dart';
import 'store.dart';
import 'synchist.dart';

class SyncService {
  /// Корневая папка данных на хранилище (задаётся при подключении).
  static String root = '/MySecureApp';

  /// Личная папка пользователя: у каждого аккаунта своя, чужие данные недоступны
  /// (и зашифрованы ключом из его собственного пароля).
  static String userId = '';
  static String get personalDir =>
      userId.isEmpty ? '$root/personal' : '$root/users/$userId';

  /// Корень общей/семейной группы: та же папка либо отдельный WebDAV (grp*).
  static String groupRoot = '/MySecureApp';
  static String get familyDir => '$groupRoot/FamilyShared';
  static String get chatDir => '$groupRoot/chat';

  /// Привязать константы к настройкам текущего профиля.
  static void bind(Settings st) {
    final f = st.folder.trim();
    root = f.isEmpty ? '/MySecureApp' : (f.startsWith('/') ? f : '/$f');
    userId = st.userId;
    if (st.groupConfigured) {
      final g = st.grpFolder.trim();
      groupRoot = g.isEmpty ? '/ASRbox-Group' : (g.startsWith('/') ? g : '/$g');
    } else {
      groupRoot = root;
    }
  }

  /// Хранилище общей группы: отдельный WebDAV, если задан, иначе то же, что личное.
  /// Так участники семьи могут быть авторизованы через разные WebDAV.
  static Remote groupOf(Settings st) {
    bind(st);
    if (st.groupConfigured) return Dav(st.grpUrl, st.grpUser, st.grpPass);
    return remoteOf(st);
  }

  /// Хранилище по настройкам: WebDAV или локальная папка.
  static Remote remoteOf(Settings st) {
    bind(st);
    if (st.storage == 'local') return LocalRemote(st.localPath);
    return Dav(st.url, st.user, st.pass);
  }

  static Future<void> run(Store s, SyncStats r, CancelToken tok) async {
    final st = s.settings;
    final dav = remoteOf(st);
    await dav.mkcolAll(root);
    if (!st.groupConfigured) await dav.mkcol('$groupRoot/profiles');
    await dav.mkcol('$root/users');
    await dav.mkcol(personalDir);
    await _settingsSync(dav, s);
    tok.check();
    final gdav = groupOf(st);
    if (st.groupConfigured) {
      await gdav.mkcolAll(groupRoot);
      await gdav.mkcol('$groupRoot/profiles');
    }
    await FamilyKeys.ensureKeyPair(s);
    await _putProfile(gdav, s);
    await FamilyKeys.fetchMine(gdav, s);
    tok.check();

    // 1. Заметки (высокий приоритет)
    await _scope(dav, s, 'personal', personalDir, s.syncKey!, r, tok);
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

    final fk = await s.familyKey();
    if (fk != null) {
      await _scope(gdav, s, 'family', familyDir, fk, r, tok);
      tok.check();
      await _comments(gdav, s, fk, r, tok);
      await _chat(gdav, s, fk, r, tok);
    } else if (s.notes.any((n) => n.vault == 'family' && !n.deleted)) {
      r.log.add('Общие заметки пропущены: нет семейного ключа, попросите владельца выдать доступ');
    }
    tok.check();

    // 3. Вложения (низкий приоритет)
    await _attachments(dav, gdav, s, fk, r, tok);
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

  static Future<void> _putProfile(Remote dav, Store s) async {
    final st = s.settings;
    await dav.put(
      '$groupRoot/profiles/${st.profileId}.json',
      utf8.encode(jsonEncode({
        'uuid': st.profileId,
        'name': s.author,
        'color': st.color,
        'pub': st.kpPub,
        'created_at': nowMs(),
      })),
    );
  }

  static Future<List<Map<String, dynamic>>> members(Store s) async {
    final st = s.settings;
    final dav = groupOf(st);
    final names = await dav.list('$groupRoot/profiles');
    final out = <Map<String, dynamic>>[];
    for (final n in names.where((e) => e.endsWith('.json'))) {
      final b = await dav.get('$groupRoot/profiles/$n');
      if (b == null) continue;
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map));
      } catch (_) {}
    }
    return out;
  }

  // ---------------------------------------------------------------- заметки

  static Future<void> _scope(Remote dav, Store s, String vault, String dir,
      SecretKey key, SyncStats r, CancelToken tok) async {
    final kind = vault == 'family' ? 'family' : 'notes';
    await dav.mkcol(dir);

    final manifest = <String, int>{};
    final mb = await dav.get('$dir/manifest.json');
    if (mb != null) {
      final m = jsonDecode(utf8.decode(mb)) as Map<String, dynamic>;
      m.forEach((k, v) => manifest[k] = (v as num).toInt());
    }
    var changed = false;
    try {

    // скачиваем изменённое на сервере
    for (final e in manifest.entries.toList()) {
      tok.check();
      final local = s.byId(e.key);
      if (local != null && local.vault != vault) continue;
      if (local != null && e.value <= local.syncedAt) continue;

      final bytes = await dav.get('$dir/${e.key}.enc');
      if (bytes == null) continue;
      final clear = await Crypto.decrypt(key, bytes);
      final remote =
          Note.fromJson(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
      remote.vault = vault;

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

    // загружаем локальные изменения
    for (final n in List<Note>.of(s.notes)) {
      tok.check();
      if (n.vault != vault) continue;
      final inManifest = manifest.containsKey(n.id);
      if (inManifest && n.updatedAt <= n.syncedAt) continue;

      final stamp = n.updatedAt;
      final data = await Crypto.encrypt(
          key, utf8.encode(jsonEncode(n.toJson(withHistory: false))));
      await dav.putAtomic('$dir/${n.id}.enc', data);
      manifest[n.id] = stamp;
      n.syncedAt = stamp;
      n.markSynced();
      r.u(kind);
      changed = true;
    }

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

  static Future<void> _comments(
      Remote dav, Store s, SecretKey fk, SyncStats r, CancelToken tok) async {
    final famNotes =
        s.notes.where((n) => n.vault == 'family' && !n.deleted).toList();
    if (famNotes.isEmpty) return;
    await dav.mkcol('$familyDir/comments');

    for (final n in famNotes) {
      tok.check();
      final d = '$familyDir/comments/${n.id}';
      final names = await dav.list(d);
      final mine = s.comments.where((c) => c.noteId == n.id).toList();
      final hasUnsynced =
          mine.any((c) => !c.synced || (c.deleted && !c.delSynced));
      if (names.isEmpty && !hasUnsynced) continue;
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

  /// Чат: каждое сообщение — отдельный файл, зашифрованный семейным ключом.
  static Future<void> _chat(
      Remote g, Store s, SecretKey fk, SyncStats r, CancelToken tok) async {
    if (!s.settings.moduleOn('chat')) return;
    await s.ensureChat();
    const room = 'general';
    final dir = '$chatDir/$room';
    var changed = false;
    final unsent = s.chat.where((m) => !m.synced).toList();
    if (unsent.isNotEmpty) {
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
    final have = s.chat.map((m) => m.id).toSet();
    for (final n in names.reversed.take(300)) {
      tok.check();
      final id = n.substring(0, n.length - 4).split('_').last;
      if (have.contains(id)) continue;
      final b = await g.get('$dir/$n');
      if (b == null) continue;
      try {
        final m = ChatMsg.fromJson(Map<String, dynamic>.from(
            jsonDecode(utf8.decode(await Crypto.decrypt(fk, b))) as Map));
        m.synced = true;
        s.chat.add(m);
        changed = true;
        r.d('chat');
      } catch (_) {
        // чужой ключ или повреждённый файл — пропускаем
      }
    }
    if (changed) {
      s.chat.sort((a, b) => a.at.compareTo(b.at));
      await s.saveChat();
      s.refresh();
    }
  }

  /// Лёгкое обновление только чата (опрос из экрана чата).
  static Future<void> chatOnly(Store s) async {
    final st = s.settings;
    if (!st.syncConfigured && !st.groupConfigured) return;
    final fk = await s.familyKey();
    if (fk == null) return;
    final g = groupOf(st);
    await _chat(g, s, fk, SyncStats(), CancelToken());
  }

  static Future<void> _attachments(
      Remote dav, Remote gdav, Store s, SecretKey? fk, SyncStats r, CancelToken tok) async {
    final mode = s.settings.attMode;
    if (mode == 'off') return;
    if (mode == 'wifi' && !await _onWifi()) return;

    final done = s.settings.attDone;
    final noteIds = {for (final x in s.notes) x.id};
    for (final n in List<Note>.of(s.notes)) {
      tok.check();
      if (n.deleted) continue;
      final family = n.vault == 'family';
      final key = family ? fk : s.syncKey;
      if (key == null) continue;
      final dir = '${family ? familyDir : personalDir}/attachments';
      final rm = family ? gdav : dav;
      var dirMade = false;

      for (final id in n.attachmentIds()) {
        if (noteIds.contains(id)) continue; // ссылка на заметку, а не на файл
        final tag = '${n.vault}:$id';
        if (s.hasAttachment(id)) {
          if (done.contains(tag)) continue;
          final plain = await s.readAttachment(id);
          if (plain == null) continue;
          if (!dirMade) {
            await rm.mkcol(dir);
            dirMade = true;
          }
          await rm.putAtomic('$dir/$id.enc', await Crypto.encrypt(key, plain));
          done.add(tag);
          r.u('attachments');
        } else {
          final bytes = await rm.get('$dir/$id.enc');
          if (bytes == null) continue;
          final plain = await Crypto.decrypt(key, bytes);
          await s.writeAttachment(id, plain);
          done.add(tag);
          r.d('attachments');
        }
      }
    }
  }
}
