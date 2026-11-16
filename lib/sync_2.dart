// ▸ Часть sync.dart: SyncService: обмен с сервером (заметки, события, папки, группы, вложения, чат, комментарии, пароли)  [содержит: SyncScopes]
part of 'sync.dart';

class SyncScopes {


  static Future<void> _group(Store s, Group g, SyncStats r, CancelToken tok, {bool auto = false}) async {
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
    // профиль: перезаписываем только при изменении или раз в 30 минут (метка «был онлайн»)
    final ph = Object.hash(g.myName, s.author, s.settings.color, g.rights, g.owner == s.settings.profileId);
    if (SyncService._profHash[g.id] != ph || nowMs() - (SyncService._profAt[g.id] ?? 0) > 30 * 60000) {
      await Groups.putProfile(dav, g, s);
      SyncService._profHash[g.id] = ph;
      SyncService._profAt[g.id] = nowMs();
    }
    await _scope(dav, s, g.vault, g.notesDir, key, g, r, tok);
    tok.check();
    if (!auto || s.settings.sharedComments) await SyncChat._comments(dav, s, g, key, r, tok);
    await SyncChat._chat(dav, s, g, key, r, tok);
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
}
