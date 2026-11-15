import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/models.dart';
import 'package:mysecure_notes/store.dart';
import 'package:mysecure_notes/sync.dart';
import 'package:mysecure_notes/synchist.dart';
import 'package:mysecure_notes/util.dart';

/// Автотесты синхронизации: два «устройства» с общей папкой на диске.
/// Главное — поймать потерю данных при одновременных правках.
void main() {
  late Directory tmp;
  late Directory shared;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('asrbox_sync_');
    shared = Directory('${tmp.path}/cloud')..createSync();
  });
  tearDown(() async => tmp.delete(recursive: true));

  Store device(String name) {
    final s = Store();
    final d = Directory('${tmp.path}/$name')..createSync(recursive: true);
    s.baseDir = d;
    s.dir = d;
    s.key = SecretKey(List<int>.generate(32, (i) => name.codeUnitAt(0) + i)); // у каждого свой
    s.syncKey = SecretKey(List<int>.filled(32, 7)); // общий ключ аккаунта
    s.settings.storage = 'local';
    s.settings.localPath = shared.path;
    s.settings.userId = 'u1';
    s.settings.attMode = 'off';
    s.settings.profileId = 'p-$name';
    return s;
  }

  Future<SyncStats> sync(Store s) async {
    final r = SyncStats();
    SyncService.bind(s.settings);
    await SyncService.run(s, r, CancelToken());
    return r;
  }

  void edit(Note n, void Function() f) {
    f();
    n.updatedAt = max(nowMs(), n.updatedAt + 1);
  }

  Note twoBlocks(Store s) {
    final n = Note.create('A', s.settings.profileId, 'personal');
    n.title = 'Список';
    n.blocks = [Block(type: 'text', content: 'one'), Block(type: 'text', content: 'two')];
    s.notes.add(n);
    return n;
  }

  test('новая заметка с первого устройства появляется на втором', () async {
    final a = device('a'), b = device('b');
    final n = twoBlocks(a);
    await sync(a);
    await sync(b);
    final got = b.byId(n.id);
    expect(got, isNotNull);
    expect(got!.title, 'Список');
    expect(got.blocks.map((x) => x.content), ['one', 'two']);
  });

  test('правки разных блоков сливаются без потерь', () async {
    final a = device('a'), b = device('b');
    final n = twoBlocks(a);
    await sync(a);
    await sync(b);
    final nb = b.byId(n.id)!;
    edit(n, () => n.blocks[0].content = 'ONE!');
    edit(nb, () => nb.blocks[1].content = 'TWO!');
    await sync(a);
    final r = await sync(b);
    expect(r.conflicts, 0);
    await sync(a);
    for (final s in [a, b]) {
      final got = s.byId(n.id)!;
      expect(got.blocks.map((x) => x.content), ['ONE!', 'TWO!'], reason: 'устройство ${s.settings.profileId}');
    }
  });

  test('правки одного блока: ничего не теряется, версия сохраняется копией «(конфликт)»', () async {
    final a = device('a'), b = device('b');
    final n = twoBlocks(a);
    await sync(a);
    await sync(b);
    final nb = b.byId(n.id)!;
    edit(n, () => n.blocks[0].content = 'версия A');
    edit(nb, () => nb.blocks[0].content = 'версия B');
    await sync(a);
    final r = await sync(b);
    expect(r.conflicts, 1);
    final texts = b.notes.expand((x) => x.blocks.map((y) => y.content)).toList();
    expect(texts, contains('версия A'));
    expect(texts, contains('версия B'));
    expect(b.notes.where((x) => x.title.contains('(конфликт)')).length, 1);
  });

  test('удаление на одном устройстве доходит до другого', () async {
    final a = device('a'), b = device('b');
    final n = twoBlocks(a);
    await sync(a);
    await sync(b);
    edit(n, () => n.deleted = true);
    await sync(a);
    await sync(b);
    expect(b.byId(n.id)!.deleted, isTrue);
  });

  test('повторная синхронизация без изменений ничего не передаёт', () async {
    final a = device('a');
    twoBlocks(a);
    await sync(a);
    final r = await sync(a);
    expect(r.up['notes'] ?? 0, 0);
    expect(r.down['notes'] ?? 0, 0);
  });
}
