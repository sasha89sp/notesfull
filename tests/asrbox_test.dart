import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/accounts.dart';
import 'package:mysecure_notes/crypto.dart';
import 'package:mysecure_notes/groups.dart';
import 'package:mysecure_notes/phone_data.dart';
import 'package:mysecure_notes/models.dart';
import 'package:mysecure_notes/remote.dart';
import 'package:mysecure_notes/util.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('asrbox_'));
  tearDown(() async => tmp.delete(recursive: true));

  test('LocalRemote: запись, чтение, списки, атомарная запись', () async {
    final r = LocalRemote(tmp.path);
    await r.mkcolAll('/a/b');
    await r.put('/a/b/x.bin', [1, 2, 3]);
    await r.putAtomic('/a/b/y.bin', [4, 5]);
    expect(await r.get('/a/b/x.bin'), [1, 2, 3]);
    expect(await r.get('/a/b/none'), isNull);
    expect((await r.list('/a/b'))..sort(), ['x.bin', 'y.bin']);
    expect(await r.listDirs('/a'), ['b']);
    await r.delete('/a/b/x.bin');
    expect(await r.get('/a/b/x.bin'), isNull);
    expect(() => r.get('/../etc/passwd'), throwsA(anything));
  });

  test('writeAtomic хранит .bak, readValid берёт резервную копию', () async {
    final f = File('${tmp.path}/d.enc');
    await writeAtomic(f, utf8.encode('v1'));
    await writeAtomic(f, utf8.encode('v2'));
    expect(await File('${f.path}.bak').readAsString(), 'v1');
    // основной файл «побит»
    await f.writeAsBytes([0, 1, 2]);
    final v = await readValid<String>(f, (b) async {
      final s = utf8.decode(b);
      if (s != 'v1' && s != 'v2') throw 'bad';
      return s;
    });
    expect(v, 'v1');
  });

  test('аккаунты: регистрация, вход, изоляция пользователей', () async {
    final r = LocalRemote(tmp.path);
    final uidA = await Accounts.register(r, '/ASRbox', 'Anna', 'password-A1', 'Anna');
    final uidB = await Accounts.register(r, '/ASRbox', 'Boris', 'password-B2', 'Boris');
    expect(uidA, isNot(uidB));
    expect(await Accounts.verify(r, '/ASRbox', 'anna', 'password-A1'), 'ok');
    expect(await Accounts.verify(r, '/ASRbox', 'Anna', 'wrong-pass'), 'wrong');
    expect(await Accounts.verify(r, '/ASRbox', 'Clara', 'whatever1'), 'nouser');
    expect(() => Accounts.register(r, '/ASRbox', 'ANNA', 'other-pass1', 'x'), throwsA('exists'));

    // данные Анны Борису не расшифровать
    final ka = await Accounts.syncKey('password-A1', uidA);
    final kb = await Accounts.syncKey('password-B2', uidB);
    final blob = await Crypto.encrypt(ka, utf8.encode('secret'));
    expect(() => Crypto.decrypt(kb, blob), throwsA(anything));
    expect(utf8.decode(await Crypto.decrypt(ka, blob)), 'secret');
  });

  test('настройки аккаунта едут через облако, подключение остаётся своим', () async {
    final r = LocalRemote(tmp.path);
    final uid = await Accounts.register(r, '/ASRbox', 'Anna', 'password-A1', 'Anna');
    final key = await Accounts.syncKey('password-A1', uid);
    final s1 = Settings(url: 'https://dav1', user: 'u1', pass: 'p1', userId: uid)
      ..gClientId = 'cid'
      ..gRefresh = 'rt'
      ..modules['chat'] = false
      ..settingsUpdatedAt = 123;
    await Accounts.pushSettings(r, '/ASRbox/users/$uid', key, s1);

    final m = await Accounts.pullSettings(r, '/ASRbox/users/$uid', key);
    expect(m, isNotNull);
    expect(m!.containsKey('pass'), isFalse); // пароль WebDAV не уходит в облако
    final s2 = Accounts.applySettings(Settings(url: 'https://dav2', user: 'u2', pass: 'p2'), m);
    expect(s2.gClientId, 'cid');
    expect(s2.gRefresh, 'rt');
    expect(s2.moduleOn('chat'), isFalse);
    expect(s2.moduleOn('notes'), isTrue);
    expect(s2.url, 'https://dav2');
    expect(s2.settingsUpdatedAt, 123);

    // с чужим ключом настройки не читаются
    final other = await Accounts.syncKey('password-B2', uid);
    expect(await Accounts.pullSettings(r, '/ASRbox/users/$uid', other), isNull);
  });

  test('Settings: модули и группа сериализуются', () {
    final s = Settings(grpUrl: 'https://g', grpUser: 'a', grpPass: 'b');
    s.modules['calendar'] = false;
    final j = Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(j.groupConfigured, isTrue);
    expect(j.moduleOn('calendar'), isFalse);
    expect(j.moduleOn('pass'), isTrue);
  });

  test('чат: сообщение шифруется семейным ключом и читается обратно', () async {
    final fk = await Crypto.deriveFixed('family', 'test-salt');
    final m = ChatMsg.create('general', 'p1', 'Anna', 'Привет');
    final enc = await Crypto.encrypt(fk, utf8.encode(jsonEncode(m.toWire())));
    final back = ChatMsg.fromJson(
        jsonDecode(utf8.decode(await Crypto.decrypt(fk, enc))) as Map<String, dynamic>);
    expect(back.text, 'Привет');
    expect(back.id, m.id);
    expect(m.fileName.endsWith('_${m.id}.enc'), isTrue);
  });

  test('Общая папка: приглашение (открытое и зашифрованное) разбирается обратно', () async {
    final key = await Groups.makeKey();
    final g = Group(
        id: 'g1', name: 'Семья', url: 'https://dav.example', user: 'u', pass: 'p',
        folder: '/Shared', key: key, owner: 'o1');
    for (final enc in [false, true]) {
      final text = await Groups.encode(g, '13112026200510', 'own', encrypted: enc);
      expect(text.contains('\n'), isFalse);
      final r = await Groups.parseInvite(text);
      expect(r.url, g.url);
      expect(r.user, 'u');
      expect(r.pass, 'p');
      expect(r.folder, '/Shared');
      expect(r.key, key);
      expect(r.invId, '13112026200510');
      expect(r.rights, 'own');
    }
    final enc = await Groups.encode(g, '13112026200510', 'own', encrypted: true);
    expect(enc.contains('https://dav.example'), isFalse);
    expect(enc.contains('"p"'), isFalse);
  });

  test('Общая папка: ключ из фразы стабилен, автоключ случайный', () async {
    expect(await Groups.makeKey(phrase: 'abc'), await Groups.makeKey(phrase: 'abc'));
    expect(await Groups.makeKey(), isNot(await Groups.makeKey()));
    expect(Groups.normFolder(' docs '), '/docs');
  });

  test('Общая папка: метка времени и права', () {
    expect(Groups.stamp(DateTime(2026, 11, 13, 20, 5, 10)), '13112026200510');
    expect(Groups.fileKey('a b/Я-1_x'), 'ab-1_x');
    final g = Group(id: 'g', rights: 'own');
    final mine = Note.create('Я', 'p1', 'g:g');
    final other = Note.create('Он', 'p2', 'g:g');
    expect(g.canEditNote(mine, 'p1'), isTrue);
    expect(g.canEditNote(other, 'p1'), isFalse);
    expect(g.canComment, isTrue);
    g.rights = 'view';
    expect(g.canEditNote(mine, 'p1'), isFalse);
    expect(g.canComment, isFalse);
    g.rights = 'edit';
    expect(g.canEditNote(other, 'p1'), isTrue);
  });

  test('vCard: экспорт и разбор контактов', () {
    final l = [
      {'name': 'Иван Петров', 'phones': ['+7 900 111-22-33'], 'emails': ['a@b.ru'], 'org': 'ООО', 'note': 'строка1\nстрока2'}
    ];
    final back = PhoneData.parseVcf(PhoneData.toVcf(l));
    expect(back.length, 1);
    expect(back[0]['name'], 'Иван Петров');
    expect(back[0]['phones'], ['+7 900 111-22-33']);
    expect(back[0]['note'], 'строка1\nстрока2');
  });

  test('runPool: ограничение параллельности и проброс ошибки', () async {
    var cur = 0, maxCur = 0, done = 0;
    await runPool([
      for (var i = 0; i < 20; i++)
        () async {
          cur++;
          if (cur > maxCur) maxCur = cur;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          cur--;
          done++;
        }
    ], limit: 4);
    expect(done, 20);
    expect(maxCur <= 4, isTrue);
    expect(
        () => runPool([() async => throw 'boom', () async {}], limit: 2), throwsA('boom'));
  });

  test('Crypto: JSON шифруется и читается через изолят', () async {
    final key = await Crypto.deriveFixed('p', 's');
    final big = [for (var i = 0; i < 4000; i++) {'id': 'n$i', 'text': 'строка $i ' * 5}];
    final enc = await Crypto.encryptJson(key, big);
    final back = await Crypto.decryptJson(key, enc) as List;
    expect(back.length, 4000);
    expect((back[123] as Map)['id'], 'n123');
  });
}
