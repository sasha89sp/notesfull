import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'crypto.dart';
import 'family.dart';
import 'merge.dart';
import 'models.dart';
import 'pass_store.dart';
import 'store.dart';

class Dav {
  final String base;
  final String auth;

  Dav(String url, String user, String pass)
      : base = url.replaceAll(RegExp(r'/+$'), ''),
        auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

  Uri _u(String p) => Uri.parse('$base$p');

  Future<http.Response> _send(String method, String path,
      {List<int>? body, Map<String, String>? headers}) async {
    final req = http.Request(method, _u(path));
    req.headers['Authorization'] = auth;
    if (headers != null) req.headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    final s = await req.send().timeout(const Duration(seconds: 120));
    return http.Response.fromStream(s);
  }

  void _checkAuth(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw 'Доступ запрещён (${r.statusCode}): проверьте логин и пароль приложения';
    }
  }

  /// Создать папку; ошибки (в т.ч. «уже существует») игнорируются.
  Future<void> mkcol(String path) async {
    try {
      await _send('MKCOL', path);
    } catch (_) {}
  }

  Future<Uint8List?> get(String path) async {
    final r = await _send('GET', path);
    if (r.statusCode == 404) return null;
    _checkAuth(r);
    if (r.statusCode >= 400) throw 'GET $path: ${r.statusCode}';
    return r.bodyBytes;
  }

  Future<void> put(String path, List<int> data) async {
    final r = await _send('PUT', path, body: data);
    _checkAuth(r);
    if (r.statusCode >= 300) throw 'PUT $path: ${r.statusCode}';
  }

  Future<void> delete(String path) async {
    try {
      await _send('DELETE', path);
    } catch (_) {}
  }

  /// Имена файлов в папке (без вложенных папок)
  Future<List<String>> list(String path) async {
    final r = await _send('PROPFIND', path, headers: {
      'Depth': '1',
      'Content-Type': 'application/xml',
    }, body: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>'));
    if (r.statusCode == 404) return [];
    _checkAuth(r);
    if (r.statusCode >= 400) throw 'PROPFIND $path: ${r.statusCode}';
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final re = RegExp(
        r'<(?:[A-Za-z0-9]+:)?href>\s*([^<]+?)\s*</(?:[A-Za-z0-9]+:)?href>',
        caseSensitive: false);
    final out = <String>[];
    for (final m in re.allMatches(body)) {
      final h = Uri.decodeFull(m.group(1)!);
      if (h.endsWith('/')) continue;
      out.add(h.split('/').last);
    }
    return out;
  }

  /// Атомарная загрузка: file.tmp -> MOVE -> file
  Future<void> putAtomic(String path, List<int> data) async {
    final tmp = '$path.tmp';
    await put(tmp, data);
    final r = await _send('MOVE', tmp, headers: {
      'Destination': _u(path).toString(),
      'Overwrite': 'T',
    });
    if (r.statusCode >= 300) {
      await put(path, data);
      await delete(tmp);
    }
  }
}

class _Res {
  int up = 0;
  int down = 0;
  int conflicts = 0;
}

class SyncService {
  static const String root = '/MySecureApp';
  static const String personalDir = '$root/personal';
  static const String familyDir = '$root/FamilyShared';

  static Future<String> run(Store s) async {
    final st = s.settings;
    final dav = Dav(st.url, st.user, st.pass);
    await dav.mkcol(root);
    await dav.mkcol('$root/profiles');
    await FamilyKeys.ensureKeyPair(s);
    await _putProfile(dav, s);
    await FamilyKeys.fetchMine(dav, s);
    final r = _Res();

    // 1. Заметки (высокий приоритет)
    await _scope(dav, s, 'personal', personalDir, s.syncKey!, r);

    // 2. События календаря (личные)
    await _mergeBlob(
      dav,
      '$personalDir/events.enc',
      s.syncKey!,
      s.events.map((e) => e.toJson()).toList(),
      (list) {
        s.events = list.map(CalEvent.fromJson).toList();
        r.down++;
      },
      r,
    );

    var extra = '';
    final fk = await s.familyKey();
    if (fk != null) {
      await _scope(dav, s, 'family', familyDir, fk, r);
      await _comments(dav, s, fk, r);
    } else if (s.notes.any((n) => n.vault == 'family' && !n.deleted)) {
      extra = ' (общие заметки пропущены: нет семейного ключа — попросите владельца выдать доступ)';
    }

    // 3. Вложения (низкий приоритет)
    await _attachments(dav, s, fk, r);

    final c = r.conflicts > 0 ? ', конфликтов: ${r.conflicts}' : '';
    return '↑${r.up} ↓${r.down}$c$extra';
  }

  // ---------------------------------------------------------------- профиль

  static Future<void> _putProfile(Dav dav, Store s) async {
    final st = s.settings;
    await dav.put(
      '$root/profiles/${st.profileId}.json',
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
    final dav = Dav(st.url, st.user, st.pass);
    final names = await dav.list('$root/profiles');
    final out = <Map<String, dynamic>>[];
    for (final n in names.where((e) => e.endsWith('.json'))) {
      final b = await dav.get('$root/profiles/$n');
      if (b == null) continue;
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map));
      } catch (_) {}
    }
    return out;
  }

  // ---------------------------------------------------------------- заметки

  static Future<void> _scope(Dav dav, Store s, String vault, String dir,
      SecretKey key, _Res r) async {
    await dav.mkcol(dir);

    final manifest = <String, int>{};
    final mb = await dav.get('$dir/manifest.json');
    if (mb != null) {
      final m = jsonDecode(utf8.decode(mb)) as Map<String, dynamic>;
      m.forEach((k, v) => manifest[k] = (v as num).toInt());
    }
    var changed = false;

    // скачиваем изменённое на сервере
    for (final e in manifest.entries.toList()) {
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
        r.down++;
      } else if (local.updatedAt > local.syncedAt) {
        // Изменено и там, и тут: пробуем слить по блокам / строкам / ячейкам
        final merged = mergeNotes(local, remote);
        if (merged != null) {
          final idx = s.notes.indexOf(local);
          if (idx >= 0) s.notes[idx] = merged;
          r.down++;
        } else {
          // правки пересеклись: серверную версию сохраняем копией
          remote.id = newId();
          remote.title = '${remote.title} (конфликт)';
          remote.syncedAt = 0;
          s.notes.add(remote);
          r.conflicts++;
        }
      } else {
        final idx = s.notes.indexOf(local);
        remote.history = local.history;
        remote.syncedAt = remote.updatedAt;
        remote.markSynced();
        if (idx >= 0) s.notes[idx] = remote;
        r.down++;
      }
    }

    // загружаем локальные изменения
    for (final n in List<Note>.of(s.notes)) {
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
      r.up++;
      changed = true;
    }

    if (changed) {
      await dav.putAtomic(
          '$dir/manifest.json', utf8.encode(jsonEncode(manifest)));
    }
  }

  // ---------------------------------------------------------------- слияние коллекций

  /// Слияние списка записей {id, updatedAt} по принципу «новее побеждает».
  static Future<void> _mergeBlob(
    Dav dav,
    String path,
    SecretKey key,
    List<Map<String, dynamic>> local,
    void Function(List<Map<String, dynamic>>) apply,
    _Res r,
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

    for (final e in remote) {
      merged[e['id'] as String] = e;
    }
    for (final e in local) {
      final id = e['id'] as String;
      final re = rm[id];
      if (re == null) {
        merged[id] = e;
        remoteChanged = true;
      } else {
        final lu = (e['updatedAt'] as num).toInt();
        final ru = (re['updatedAt'] as num).toInt();
        if (lu > ru) {
          merged[id] = e;
          remoteChanged = true;
        } else if (ru > lu) {
          localChanged = true;
        }
      }
    }
    for (final id in rm.keys) {
      if (!lm.containsKey(id)) localChanged = true;
    }

    final list = merged.values.toList();
    if (localChanged) apply(list);
    if (remoteChanged) {
      await dav.putAtomic(
          path, await Crypto.encrypt(key, utf8.encode(jsonEncode(list))));
      r.up++;
    }
  }

  /// Менеджер паролей (вызывается отдельно, когда хранилище паролей открыто)
  static Future<void> runPasswords(Store s, PassStore p) async {
    final st = s.settings;
    if (!st.syncConfigured || !p.unlocked || p.syncKey == null) return;
    final dav = Dav(st.url, st.user, st.pass);
    await dav.mkcol(root);
    await dav.mkcol(personalDir);
    final r = _Res();
    await _mergeBlob(
      dav,
      '$personalDir/passwords.enc',
      p.syncKey!,
      p.entries.map((e) => e.toJson()).toList(),
      (list) {
        p.entries = list.map(PassEntry.fromJson).toList();
      },
      r,
    );
  }

  // ---------------------------------------------------------------- комментарии

  static Future<void> _comments(
      Dav dav, Store s, SecretKey fk, _Res r) async {
    final famNotes =
        s.notes.where((n) => n.vault == 'family' && !n.deleted).toList();
    if (famNotes.isEmpty) return;
    await dav.mkcol('$familyDir/comments');

    for (final n in famNotes) {
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
          r.down++;
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
          r.up++;
        }
        if (c.deleted && !c.delSynced && c.file.isNotEmpty) {
          final base = c.file.substring(0, c.file.length - '.enc'.length);
          await dav.put('$d/$base.del.enc',
              await Crypto.encrypt(fk, utf8.encode('deleted')));
          c.delSynced = true;
          r.up++;
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

  static Future<void> _attachments(
      Dav dav, Store s, SecretKey? fk, _Res r) async {
    final mode = s.settings.attMode;
    if (mode == 'off') return;
    if (mode == 'wifi' && !await _onWifi()) return;

    final done = s.settings.attDone;
    for (final n in List<Note>.of(s.notes)) {
      if (n.deleted) continue;
      final family = n.vault == 'family';
      final key = family ? fk : s.syncKey;
      if (key == null) continue;
      final dir = '${family ? familyDir : personalDir}/attachments';
      var dirMade = false;

      for (final b in n.blocks) {
        final id = b.att;
        if (id == null) continue;
        final tag = '${n.vault}:$id';
        if (s.hasAttachment(id)) {
          if (done.contains(tag)) continue;
          final plain = await s.readAttachment(id);
          if (plain == null) continue;
          if (!dirMade) {
            await dav.mkcol(dir);
            dirMade = true;
          }
          await dav.putAtomic('$dir/$id.enc', await Crypto.encrypt(key, plain));
          done.add(tag);
          r.up++;
        } else {
          final bytes = await dav.get('$dir/$id.enc');
          if (bytes == null) continue;
          final plain = await Crypto.decrypt(key, bytes);
          await s.writeAttachment(id, plain);
          done.add(tag);
          r.down++;
        }
      }
    }
  }
}
