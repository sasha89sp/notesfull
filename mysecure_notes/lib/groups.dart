import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'crypto.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';
part 'groups_2.dart';


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

  /// Метка времени «ддммггггччммсс» без разделителей, например 13112026200510.
  static String stamp([DateTime? d]) {
    final x = d ?? DateTime.now();
    String t(int v, [int n = 2]) => v.toString().padLeft(n, '0');
    return '${t(x.day)}${t(x.month)}${t(x.year, 4)}${t(x.hour)}${t(x.minute)}${t(x.second)}';
  }

  /// Имя файла профиля из идентификатора: только латиница, цифры, «-» и «_».
  static String fileKey(String id) => id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '');

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

  /// Создать общую папку на указанном WebDAV (по умолчанию подставляются данные текущей авторизации).
  static Future<Group> create(Store s,
      {required String name,
      required String folder,
      required String url,
      required String user,
      required String pass,
      String? id,
      String? phrase}) async {
    final st = s.settings;
    if (url.trim().isEmpty || user.trim().isEmpty) throw 'Укажите WebDAV-сервер, логин и пароль';
    if (name.trim().isEmpty) throw 'Введите название';
    final gid = (id ?? '').trim().isEmpty ? stamp() : id!.trim();
    if (st.groups.any((x) => x.id == gid)) throw 'Группа с таким ID уже есть';
    final f = normFolder(folder);
    final dav = Dav(url.trim(), user.trim(), pass);
    await dav.mkcolAll(f);
    final g = Group(
      id: gid,
      name: name.trim(),
      url: url.trim(),
      user: user.trim(),
      pass: pass,
      folder: f,
      key: await makeKey(phrase: phrase),
      owner: st.profileId,
      myName: s.author,
      rights: 'edit',
    );
    await dav.mkcol(g.notesDir);
    await dav.mkcol(g.profilesDir);
    await dav.mkcol(g.chatDir);
    await dav.mkcol('$f/invites');
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

  /// Профиль участника в группе: имя, полный идентификатор, права и время последнего онлайна.
  static Future<void> putProfile(Remote r, Group g, Store s) async {
    final st = s.settings;
    final id = g.memberId(st.profileId);
    await r.put(
      '${g.profilesDir}/${fileKey(id)}.json',
      utf8.encode(jsonEncode({
        'uuid': id,
        'name': g.myName.isEmpty ? s.author : g.myName,
        'color': st.color,
        'rights': g.owner == st.profileId ? 'owner' : g.rights,
        'lastSeen': nowMs(),
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
    final me = g.memberId(s.settings.profileId);
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
      await r.delete('${g.profilesDir}/${fileKey(remove)}.json');
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
  }}