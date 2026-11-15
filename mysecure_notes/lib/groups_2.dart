part of 'groups.dart';

class GroupsInvite {


  // ------------------------------------------------------------ приглашение

  static const _plain = 'asrbox-g1:';
  static const _enc = 'asrbox-g1e:';

  static Map<String, dynamic> _payload(Group g, String invId, String rights) => {
        'i': g.id,
        'g': g.name,
        'u': g.url,
        'n': g.user,
        'p': g.pass,
        'f': g.folder,
        'k': g.key,
        'o': g.owner,
        'v': invId,
        'r': rights,
      };

  static Future<SecretKey> _inviteKey() =>
      Crypto.deriveFixed('asrbox-invite', 'asrbox-invite-v1');

  /// Создаёт приглашение: новый уникальный ID (дата и время с секундами), запись о нём
  /// на сервере (права и разовость) и строку для копирования. Зашифрованное приглашение
  /// не показывает получателю логин и пароль WebDAV (защита от случайного просмотра).
  static Future<String> makeInvite(Group g,
      {required bool encrypted, required String rights, required bool single}) async {
    final r = Groups.remoteOf(g);
    await r.mkcolAll('${g.folder}/invites');
    var inv = Groups.stamp();
    var n = 0;
    while (await r.get('${g.folder}/invites/$inv.json') != null) {
      n++;
      inv = '${stamp()}$n';
    }
    await r.putAtomic(
        '${g.folder}/invites/$inv.json',
        utf8.encode(jsonEncode({
          'id': inv,
          'rights': rights,
          'single': single,
          'created': nowMs(),
          'by': g.memberId(''),
        })));
    return encode(g, inv, rights, encrypted: encrypted);
  }

  static Future<String> encode(Group g, String inv, String rights,
      {required bool encrypted}) async {
    final json = utf8.encode(jsonEncode(_payload(g, inv, rights)));
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
        invId: (m['v'] ?? '') as String,
        rights: (m['r'] ?? 'edit') as String,
      );
      if (g.id.isEmpty || g.url.isEmpty || g.folder.isEmpty || g.key.isEmpty) throw 'поля';
      return g;
    } catch (_) {
      throw 'Приглашение не распознано. Скопируйте строку целиком.';
    }
  }

  /// Войти в общую группу по приглашению.
  /// Войти в группу по приглашению. Имя обязательно: без него доступ не выдаётся.
  static Future<Group> join(Store s, String inviteText, String name) async {
    final nm = name.trim();
    if (nm.isEmpty) throw 'Введите своё имя: без него доступ не выдаётся';
    final g = await parseInvite(inviteText);
    final dav = Groups.remoteOf(g);
    final meta = await dav.get('${g.folder}/meta.json');
    if (meta == null) throw 'Папка группы не найдена или нет доступа к WebDAV';
    final chk = await dav.get('${g.folder}/check.enc');
    if (chk != null) {
      try {
        await Crypto.decrypt(Groups.keyOf(g), chk);
      } catch (_) {
        throw 'Неверный ключ шифрования в приглашении';
      }
    }
    try {
      final m = jsonDecode(utf8.decode(meta)) as Map<String, dynamic>;
      if (g.name.isEmpty) g.name = (m['name'] ?? 'Группа') as String;
      if (g.owner.isEmpty) g.owner = (m['owner'] ?? '') as String;
    } catch (_) {}
    final inv = g.invId.isEmpty ? g.id : g.invId;
    final myId = '$inv${stamp()}$nm';
    // запись о приглашении на сервере: права и разовость нельзя подменить в строке
    final recB = await dav.get('${g.folder}/invites/$inv.json');
    if (recB != null) {
      try {
        final rec = jsonDecode(utf8.decode(recB)) as Map<String, dynamic>;
        g.rights = (rec['rights'] ?? g.rights) as String;
        if (rec['single'] == true) {
          final used = await dav.get('${g.folder}/invites/$inv.used');
          const msg = 'Такой пользователь уже зарегистрировался, повторно нельзя';
          if (used != null) throw msg;
          await dav.putAtomic('${g.folder}/invites/$inv.used', utf8.encode(myId));
          final back = await dav.get('${g.folder}/invites/$inv.used');
          if (back == null || utf8.decode(back) != myId) throw msg;
        }
      } on FormatException {
        // повреждённая запись: считаем приглашение обычным
      }
    } else if (g.invId.isNotEmpty) {
      throw 'Приглашение недействительно или отозвано';
    }
    g.me = myId;
    g.myName = nm;
    final st = s.settings;
    st.groups.removeWhere((x) => x.id == g.id);
    st.groups.add(g);
    await s.saveSettings();
    try {
      await Groups.putProfile(dav, g, s);
    } catch (_) {}
    return g;
  }
}
