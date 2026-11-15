part of 'sync.dart';

class SyncChat {


  /// Менеджер паролей (вызывается отдельно, когда хранилище паролей открыто)
  static Future<void> runPasswords(Store s, PassStore p) async {
    final st = s.settings;
    if (!st.syncConfigured || !p.unlocked || p.syncKey == null) return;
    final dav = SyncService.remoteOf(st);
    await dav.mkcolAll(SyncService.root);
    await dav.mkcol('$root/users');
    await dav.mkcol(SyncService.personalDir);
    final r = SyncStats();
    await SyncScopes._mergeBlob(
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
