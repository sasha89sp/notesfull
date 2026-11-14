import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'crypto.dart';
import 'models.dart';
import 'remote.dart';

/// Реестр аккаунтов ASRbox на хранилище: `<папка>/accounts/<uid>.json`.
/// Один WebDAV могут использовать несколько людей: у каждого свой логин и пароль,
/// своя папка `users/<uid>` и свой ключ шифрования. Пароль в облако не попадает,
/// в реестре лежит только зашифрованная проверочная метка.
class Accounts {
  static const _salt = 'asrbox-account-v2:';

  /// Идентификатор аккаунта по логину (без учёта регистра).
  static Future<String> uidFor(String login) async {
    final h = await Sha256().hash(utf8.encode('asrbox:${login.trim().toLowerCase()}'));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 24);
  }

  /// Ключ синхронизации личных данных аккаунта.
  static Future<SecretKey> syncKey(String pw, String uid) =>
      Crypto.deriveFixed(pw, 'asrbox-sync-v2:$uid');

  static String _normRoot(String f) {
    final t = f.trim();
    if (t.isEmpty) return '/ASRbox';
    return t.startsWith('/') ? t : '/$t';
  }

  /// Подпапки корня хранилища: для выбора существующей папки.
  static Future<List<String>> folders(Remote r, [String at = '/']) async {
    final l = await r.listDirs(at);
    l.sort();
    return l;
  }

  /// Есть ли в папке данные ASRbox/MySecureApp.
  static Future<bool> looksLikeData(Remote r, String folder) async {
    final f = _normRoot(folder);
    final d = await r.listDirs(f);
    return d.contains('accounts') || d.contains('personal') || d.contains('users');
  }

  /// Результат: ok | nouser | wrong | error:...
  static Future<String> verify(Remote r, String folder, String login, String pw) async {
    try {
      final uid = await uidFor(login);
      final b = await r.get('${_normRoot(folder)}/accounts/$uid.json');
      if (b == null) return 'nouser';
      final m = jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
      final k = await Crypto.deriveFixed(pw, '$_salt$uid');
      try {
        final ok = await Crypto.decrypt(k, base64Decode(m['check'] as String));
        return utf8.decode(ok) == 'asrbox' ? 'ok' : 'wrong';
      } catch (_) {
        return 'wrong';
      }
    } catch (e) {
      return 'error:$e';
    }
  }

  /// Создать аккаунт. Бросает 'exists', если логин уже занят.
  static Future<String> register(
      Remote r, String folder, String login, String pw, String name) async {
    final f = _normRoot(folder);
    final uid = await uidFor(login);
    await r.mkcolAll(f);
    await r.mkcol('$f/accounts');
    await r.mkcol('$f/users');
    if (await r.get('$f/accounts/$uid.json') != null) throw 'exists';
    final k = await Crypto.deriveFixed(pw, '$_salt$uid');
    final check = await Crypto.encrypt(k, utf8.encode('asrbox'));
    await r.putAtomic(
        '$f/accounts/$uid.json',
        utf8.encode(jsonEncode({
          'v': 2,
          'uid': uid,
          'name': name,
          'check': base64Encode(check),
          'created_at': nowMs(),
        })));
    await r.mkcol('$f/users/$uid');
    return uid;
  }

  /// Смена пароля аккаунта: перешифровывается только метка; данные
  /// перешифровываются при следующей синхронизации (делает Store).
  // ------------------------------------------------------------ настройки

  /// Поля, которые не переносятся между устройствами (способ подключения к
  /// хранилищу и данные самого аккаунта определяются при входе).
  static const _skip = {'url', 'user', 'pass', 'storage', 'folder', 'localPath', 'userId', 'uiMode', 'bgSync', 'paneW', 'paneOrder', 'fontScale', 'modLock'};

  static Map<String, dynamic> exportSettings(Settings s) {
    final m = Map<String, dynamic>.from(s.toJson());
    for (final k in _skip) {
      m.remove(k);
    }
    return m;
  }

  /// Применяет настройки из облака: служебные поля подключения сохраняются.
  static Settings applySettings(Settings cur, Map<String, dynamic> m) {
    final j = Map<String, dynamic>.from(cur.toJson());
    for (final e in m.entries) {
      if (!_skip.contains(e.key)) j[e.key] = e.value;
    }
    return Settings.fromJson(j);
  }

  static Future<void> pushSettings(Remote r, String dir, SecretKey key, Settings s) async {
    final data = await Crypto.encrypt(key, utf8.encode(jsonEncode(exportSettings(s))));
    await r.putAtomic('$dir/settings.enc', data);
  }

  /// Забирает настройки из облака. Возвращает null, если их там нет/не расшифровались.
  static Future<Map<String, dynamic>?> pullSettings(Remote r, String dir, SecretKey key) async {
    try {
      final b = await r.get('$dir/settings.enc');
      if (b == null) return null;
      final d = await Crypto.decrypt(key, b);
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(d)) as Map);
    } catch (_) {
      return null;
    }
  }
}
