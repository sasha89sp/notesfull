import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/accounts.dart';
import 'package:mysecure_notes/crypto.dart';
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
}
