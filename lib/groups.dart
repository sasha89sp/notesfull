import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'crypto.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';

/// Общие папки (группы). У каждой свой WebDAV, своя папка и свой ключ шифрования
/// (тип 2): участники могут входить в приложение через разные хранилища.
class Groups {
  static Remote remoteOf(Group g) => Dav(g.url, g.user, g.pass);
  static SecretKey keyOf(Group g) => SecretKey(base64Decode(g.key));

  static Group? byVault(Settings st, String vault) {
    for (final g in st.groups) {
      if (g.vault == vault) return g;
    }
    return null;
  }

  static Group? byId(Settings st, String id) {
    for (final g in st.groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  static String normFolder(String f) {
    final t = f.trim();
    if (t.isEmpty) return '/ASRbox-Shared';
    return t.startsWith('/') ? t : '/$t';
  }

  /// Новый ключ: случайный или выведенный из придуманной фразы.
  static Future<String> makeKey({String? phrase}) async {
    if (phrase != null && phrase.isNotEmpty) {
      final k = await Crypto.deriveFixed(phrase, 'asrbox-group-key-v1');
      return base64Encode(await k.extractBytes());
    }
    final r = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  // ------------------------------------------------------------ создание

  /// Создать общую папку на WebDAV, к которому вы подключены.
  static Future<Group> create(Store s,
      {required String name, required String folder, String? phrase}) async {
    final st = s.settings;
    if (st.storage != 'webdav' || !st.syncConfigured) {
      throw 'Сначала подключитесь к WebDAV (Настройки)';
    }
    if (name.trim().isEmpty) throw 'Введите название';
    final f = normFolder(folder);
    final dav = Dav(st.url, st.user, st.pass);
    await dav.mkcolAll(f);
    final g = Group(
      id: newId(),
      name: name.trim(),
      url: st.url,
      user: st.user,
      pass: st.pass,
      folder: f,
      key: await makeKey(phrase: phrase),
      owner: st.profileId,
    );
    await dav.mkcol(g.notesDir);
    await dav.mkcol(g.profilesDir);
    await dav.mkcol(g.chatDir);
    await dav.putAtomic(
        '$f/meta.json',
        utf8.encode(jsonEncode(
            {'id': g.id, 'name': g.name, 'owner': g.owner, 'created': nowMs()})));
    // проверочная метка: по ней вошедший по приглашению убеждается, что ключ верный
    await dav.putAtomic(
        '$f/check.enc', await Crypto.encrypt(keyOf(g), utf8.encode('asrbox-group')));
    await dav.putAtomic('$f/acl.json',
        utf8.encode(jsonEncode({'owner': g.owner, 'removed': [], 'readonly': []})));
    st.groups.add(g);
    await s.saveSettings();
    return g;
  }

  // ------------------------------------------------------------ приглашение

  static const _plain = 'asrbox-g1:';
  static const _enc = 'asrbox-g1e:';

  static Map<String, dynamic> _payload(Group g) => {
        'i': g.id,
        'g': g.name,
        'u': g.url,
        'n': g.user,
        'p': g.pass,
        'f': g.folder,
        'k': g.key,
        'o': g.owner,
      };

  static Future<SecretKey> _inviteKey() =>
      Crypto.deriveFixed('asrbox-invite', 'asrbox-invite-v1');

  /// Приглашение одной строкой. В открытом виде содержимое видно полностью;
  /// зашифрованное не показывает получателю логин и пароль WebDAV (приложение
  /// подставит их само). Это защита от случайного просмотра в переписке и буфере обмена.
  static Future<String> invite(Group g, {required bool encrypted}) async {
    final json = utf8.encode(jsonEncode(_payload(g)));
    if (!encrypted) return '$_plain${base64Url.encode(json)}';
    final data = await Crypto.encrypt(await _inviteKey(), json);
    return '$_enc${base64Url.encode(data)}';
  }

  /// Разбор приглашения. Бросает понятную ошибку, если строка не подходит.
  static Future<Group> parseInvite(String text) async {
    final t = text.trim().replaceAll(RegExp(r'\s+'), '');
    List<int> json;
    try {
      if (t.startsWith(_enc)) {
        final data = base64Url.decode(base64Url.normalize(t.substring(_enc.length)));
        json = await Crypto.decrypt(await _inviteKey(), data);
      } else if (t.startsWith(_plain)) {
        json = base64Url.decode(base64Url.normalize(t.substring(_plain.length)));
      } else {
        throw 'формат';
      }
      final m = jsonDecode(utf8.decode(json)) as Map<String, dynamic>;
      final g = Group(
        id: (m['i'] ?? '') as String,
        name: (m['g'] ?? '') as String,
        url: (m['u'] ?? '') as String,
        user: (m['n'] ?? '') as String,
        pass: (m['p'] ?? '') as String,
        folder: (m['f'] ?? '') as String,
        key: (m['k'] ?? '') as String,
        owner: (m['o'] ?? '') as String,
      );
      if (g.id.isEmpty || g.url.isEmpty || g.folder.isEmpty || g.key.isEmpty) throw 'поля';
      return g;
    } catch (_) {
      throw 'Приглашение не распознано. Скопируйте строку целиком.';
    }
  }

  /// Войти в общую группу по приглашению.
  static Future<Group> join(Store s, String inviteText) async {
    final g = await parseInvite(inviteText);
    final dav = remoteOf(g);
    final meta = await dav.get('${g.folder}/meta.json');
    if (meta == null) throw 'Папка группы не найдена или нет доступа к WebDAV';
    final chk = await dav.get('${g.folder}/check.enc');
    if (chk != null) {
      try {
        await Crypto.decrypt(keyOf(g), chk);
      } catch (_) {
        throw 'Неверный ключ шифрования в приглашении';
      }
    }
    try {
      final m = jsonDecode(utf8.decode(meta)) as Map<String, dynamic>;
      if (g.name.isEmpty) g.name = (m['name'] ?? 'Группа') as String;
      if (g.owner.isEmpty) g.owner = (m['owner'] ?? '') as String;
    } catch (_) {}
    final st = s.settings;
    st.groups.removeWhere((x) => x.id == g.id);
    st.groups.add(g);
    await s.saveSettings();
    return g;
  }

  /// Покинуть группу на этом устройстве (общие заметки группы удаляются локально).
  static Future<void> leave(Store s, Group g) async {
    s.notes.removeWhere((n) => n.vault == g.vault);
    s.chat.removeWhere((m) => m.room == g.id);
    s.settings.groups.removeWhere((x) => x.id == g.id);
    await s.saveSettings();
    await s.saveChat();
    s.changed();
  }

  // ------------------------------------------------------------ участники и права

  static Future<void> putProfile(Remote r, Group g, Store s) async {
    final st = s.settings;
    await r.put(
      '${g.profilesDir}/${st.profileId}.json',
      utf8.encode(jsonEncode({
        'uuid': st.profileId,
        'name': s.author,
        'color': st.color,
        'created_at': nowMs(),
      })),
    );
  }

  static Future<List<Map<String, dynamic>>> members(Group g) async {
    final r = remoteOf(g);
    final out = <Map<String, dynamic>>[];
    for (final n in (await r.list(g.profilesDir)).where((e) => e.endsWith('.json'))) {
      final b = await r.get('${g.profilesDir}/$n');
      if (b == null) continue;
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map));
      } catch (_) {}
    }
    return out;
  }

  static Future<Map<String, dynamic>> readAcl(Remote r, Group g) async {
    try {
      final b = await r.get('${g.folder}/acl.json');
      if (b == null) return {'owner': g.owner, 'removed': [], 'readonly': []};
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map);
    } catch (_) {
      return {'owner': g.owner, 'removed': [], 'readonly': []};
    }
  }

  /// Применяет права из облака к этому устройству (вызывается при синхронизации).
  static Future<void> applyAcl(Remote r, Group g, Store s) async {
    final acl = await readAcl(r, g);
    final me = s.settings.profileId;
    final removed = ((acl['removed'] ?? []) as List).map((e) => e.toString()).toSet();
    final ro = ((acl['readonly'] ?? []) as List).map((e) => e.toString()).toSet();
    g.removed = removed.contains(me);
    g.readOnly = ro.contains(me) && g.owner != me;
  }

  /// Только владелец. [remove] — убрать участника, [readonly] — запретить/разрешить правки.
  static Future<void> setAcl(Group g, Store s,
      {String? remove, String? readonlyId, bool readonly = false}) async {
    if (g.owner != s.settings.profileId) throw 'Права меняет только создатель папки';
    final r = remoteOf(g);
    final acl = await readAcl(r, g);
    final removed = ((acl['removed'] ?? []) as List).map((e) => e.toString()).toSet();
    final ro = ((acl['readonly'] ?? []) as List).map((e) => e.toString()).toSet();
    if (remove != null) {
      removed.add(remove);
      ro.remove(remove);
      await r.delete('${g.profilesDir}/$remove.json');
    }
    if (readonlyId != null) {
      if (readonly) {
        ro.add(readonlyId);
      } else {
        ro.remove(readonlyId);
      }
    }
    await r.putAtomic(
        '${g.folder}/acl.json',
        utf8.encode(jsonEncode(
            {'owner': g.owner, 'removed': removed.toList(), 'readonly': ro.toList()})));
  }

  static Future<Set<String>> readonlyIds(Group g) async {
    final acl = await readAcl(remoteOf(g), g);
    return ((acl['readonly'] ?? []) as List).map((e) => e.toString()).toSet();
  }

  /// Перенос данных прежней версии («Семья») в группу.
  static Future<void> migrateLegacy(Store s) async {
    final st = s.settings;
    if (st.groups.any((g) => g.legacy)) return;
    String key = '';
    if (st.famKey.isNotEmpty) {
      key = st.famKey;
    } else if (st.familyPass.isNotEmpty) {
      final k = await Crypto.deriveFixed(st.familyPass, 'mysecure-family-v1');
      key = base64Encode(await k.extractBytes());
    }
    if (key.isEmpty) return;
    final sep = st.groupConfigured;
    final f = sep ? st.grpFolder : st.folder;
    st.groups.add(Group(
      id: 'legacy',
      name: 'Семья',
      url: sep ? st.grpUrl : st.url,
      user: sep ? st.grpUser : st.user,
      pass: sep ? st.grpPass : st.pass,
      folder: normFolder(f.isEmpty ? '/MySecureApp' : f),
      key: key,
      owner: '',
      legacy: true,
    ));
    await s.saveSettings();
  }
}
