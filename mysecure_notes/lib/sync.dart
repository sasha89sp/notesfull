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
part 'sync_2.dart';
part 'sync_3.dart';


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

  static Future<void> run(Store s, SyncStats r, CancelToken tok, {bool auto = false}) async {
    final st = s.settings;
    final dav = remoteOf(st);
    await dav.mkcolAll(root);
    await dav.mkcol('$root/users');
    await dav.mkcol(personalDir);
    await _settingsSync(dav, s);
    tok.check();
    tok.check();

    // 1. Заметки (высокий приоритет)
    await SyncScopes._scope(dav, s, 'personal', personalDir, s.syncKey!, null, r, tok);
    tok.check();

    // 2. События календаря (личные)
    await SyncScopes._mergeBlob(
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
    await SyncScopes._mergeBlob(
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
    final sharedDue = !auto || _sharedDue(s);
    if (sharedDue && st.groups.isNotEmpty) st.sharedLast = nowMs();
    for (final g in List<Group>.of(st.groups)) {
      tok.check();
      if (!sharedDue) break;
      if (g.removed || g.key.isEmpty) continue;
      try {
        await SyncScopes._group(s, g, r, tok, auto: auto);
      } on SyncCancelled {
        rethrow;
      } catch (e) {
        r.log.add('Общая папка «${g.name}»: $e');
      }
    }
    tok.check();

    // 3. Вложения (низкий приоритет)
    await SyncChat._attachments(dav, s, r, tok);
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
  /// Пора ли трогать общие папки при автоматической синхронизации:
  /// есть несинхронизированные локальные изменения или прошёл заданный интервал.
  static bool _sharedDue(Store s) {
    final st = s.settings;
    if (st.groups.isEmpty) return false;
    final dirty = s.notes.any((n) => n.vault != 'personal' && n.syncedAt < n.updatedAt) ||
        s.comments.any((c) => !c.synced || (c.deleted && !c.delSynced));
    if (dirty) return true;
    if (st.sharedEvery <= 0) return false;
    return nowMs() - st.sharedLast >= Duration(minutes: st.sharedEvery).inMilliseconds;
  }

  static final Map<String, int> _profAt = {};
  static final Map<String, int> _profHash = {};}