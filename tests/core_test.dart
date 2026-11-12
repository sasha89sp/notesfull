import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/backup.dart';
import 'package:mysecure_notes/crypto.dart';
import 'package:mysecure_notes/family.dart';
import 'package:mysecure_notes/formula.dart';
import 'package:mysecure_notes/ics.dart';
import 'package:mysecure_notes/merge.dart';
import 'package:mysecure_notes/models.dart';
import 'package:mysecure_notes/totp.dart';
import 'package:mysecure_notes/util.dart';
import 'package:mysecure_notes/xlsx.dart';

Note _note(String text, {List<Block>? base}) {
  final n = Note.create('A', 'a', 'personal');
  n.blocks = [Block(id: 'b1', type: 'text', content: text)];
  if (base != null) {
    n.base = base;
    n.baseTitle = '';
  }
  return n;
}

void main() {
  test('шифрование: туда и обратно, чужой ключ не подходит', () async {
    final k = await Crypto.deriveFixed('пароль', 'salt-1');
    final data = utf8.encode('секретная заметка');
    final enc = await Crypto.encrypt(k, data);
    expect(enc, isNot(equals(data)));
    expect(await Crypto.decrypt(k, enc), data);
    final other = await Crypto.deriveFixed('другой', 'salt-1');
    await expectLater(Crypto.decrypt(other, enc), throwsA(anything));
  });

  test('TOTP: вектор RFC 6238', () async {
    final code = await totpCode(
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      at: DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
    );
    expect(code, '287082');
  });

  test('формулы', () {
    final t = TableData.empty(4, 3);
    t.cells[0][0].v = '2';
    t.cells[1][0].v = '3';
    t.cells[2][0].v = '=SUM(A1:A2)';
    t.cells[0][1].v = '=A1*A2+1';
    t.cells[1][1].v = '=1/0';
    t.cells[2][1].v = '=AVERAGE(A1:A2)';
    t.cells[0][2].v = '=C2';
    t.cells[1][2].v = '=C1';
    final ev = Evaluator(t);
    expect(ev.display(2, 0), '5');
    expect(ev.display(0, 1), '7');
    expect(ev.display(1, 1), '#ДЕЛ/0!');
    expect(ev.display(2, 1), '2.5');
    expect(ev.display(0, 2), '#ЦИКЛ!');
  });

  test('имена столбцов', () {
    expect(colName(0), 'A');
    expect(colName(25), 'Z');
    expect(colName(26), 'AA');
    expect(colIndex('AA'), 26);
  });

  test('CSV с кавычками и запятыми', () {
    final rows = parseCsv('a,b\n"x, y","он сказал ""да"""\n');
    expect(rows.length, 2);
    expect(rows[1][0], 'x, y');
    expect(rows[1][1], 'он сказал "да"');
    expect(parseCsv(toCsv(rows)), rows);
  });

  test('.ics: экспорт и импорт', () {
    final e = CalEvent.create(DateTime(2026, 11, 20, 10));
    e.title = 'Встреча, важная';
    e.notes = 'строка 1\nстрока 2';
    final back = Ics.import(Ics.export([e]));
    expect(back.length, 1);
    expect(back.first.title, 'Встреча, важная');
    expect(back.first.notes, 'строка 1\nстрока 2');
    expect(back.first.start, e.start);
  });

  test('.xlsx: экспорт и импорт', () {
    final t = TableData.empty(3, 3);
    t.cells[0][0].v = 'Имя';
    t.cells[0][1].v = '10';
    t.cells[1][1].v = '=B1*2';
    t.mergeRange(2, 0, 2, 1);
    final back = Xlsx.import(Xlsx.export(t, 'Лист'));
    expect(back.cells[0][0].v, 'Имя');
    expect(back.cells[0][1].v, '10');
    expect(back.cells[1][1].v, '=B1*2');
    expect(back.merges.length, 1);
  });

  group('слияние заметок', () {
    test('разные строки одного блока сливаются', () {
      final base = [Block(id: 'b1', type: 'text', content: 'a\nb\nc')];
      final local = _note('A\nb\nc', base: base);
      final remote = _note('a\nb\nC');
      final m = mergeNotes(local, remote);
      expect(m, isNotNull);
      expect(m!.blocks.single.content, 'A\nb\nC');
    });

    test('одна и та же строка — конфликт', () {
      final base = [Block(id: 'b1', type: 'text', content: 'a\nb\nc')];
      final local = _note('X\nb\nc', base: base);
      final remote = _note('Y\nb\nc');
      expect(mergeNotes(local, remote), isNull);
    });

    test('добавленные блоки объединяются', () {
      final base = [Block(id: 'b1', type: 'text', content: 'a')];
      final local = _note('a', base: base)
        ..blocks.add(Block(id: 'l2', type: 'quote', content: 'мой'));
      final remote = _note('a')
        ..blocks.add(Block(id: 'r2', type: 'code', content: 'чужой'));
      final m = mergeNotes(local, remote)!;
      expect(m.blocks.map((b) => b.id).toList(), ['b1', 'l2', 'r2']);
    });

    test('таблица: разные ячейки сливаются', () {
      Block tb(String a, String b) {
        final t = TableData.empty(2, 2);
        t.cells[0][0].v = a;
        t.cells[1][1].v = b;
        final bl = Block(id: 't', type: 'table');
        bl.table = t;
        return bl;
      }

      final local = Note.create('A', 'a', 'personal')
        ..blocks = [tb('1', '')]
        ..base = [tb('', '')];
      final remote = Note.create('B', 'b', 'personal')..blocks = [tb('', '2')];
      final m = mergeNotes(local, remote)!;
      final t = m.blocks.single.table;
      expect(t.cells[0][0].v, '1');
      expect(t.cells[1][1].v, '2');
    });

    test('без базы слияние не выполняется', () {
      expect(mergeNotes(_note('a'), _note('b')), isNull);
    });
  });

  test('семейный ключ: обёртка X25519', () async {
    final a = Settings();
    final kp = await X25519().newKeyPair();
    a.kpPriv = base64Encode(await kp.extractPrivateKeyBytes());
    a.kpPub = base64Encode((await kp.extractPublicKey()).bytes);
    final key = List<int>.generate(32, (i) => i * 7 % 256);
    final w = await FamilyKeys.wrap(key, a.kpPub);
    expect(await FamilyKeys.unwrap(w, a), key);

    final b = Settings();
    final kp2 = await X25519().newKeyPair();
    b.kpPriv = base64Encode(await kp2.extractPrivateKeyBytes());
    b.kpPub = base64Encode((await kp2.extractPublicKey()).bytes);
    await expectLater(FamilyKeys.unwrap(w, b), throwsA(anything));
  });

  test('Joplin JEX: экспорт и повторный разбор', () {
    final f1 = NoteFolder(id: 'f1', name: 'Работа', updatedAt: 1);
    final f2 = NoteFolder(id: 'f2', name: 'Идеи', parent: 'f1', updatedAt: 1);
    final n = Note.create('Я', 'me', 'personal')
      ..title = 'План'
      ..folder = 'f2'
      ..tags = ['важное']
      ..blocks = [
        Block(type: 'text', content: 'Первая строка\nвторая'),
        Block(type: 'checklist', items: [CheckItem('молоко', true), CheckItem('хлеб')]),
        Block(type: 'file', meta: {'att': 'a1', 'name': 'doc.txt'}),
      ];
    final tar = Jex.export([f1, f2], [n], {'a1': utf8.encode('hello')});
    final p = Jex.parse(tar);
    expect(p.folders.length, 2);
    final child = p.folders.firstWhere((f) => f.title == 'Идеи');
    final parent = p.folders.firstWhere((f) => f.title == 'Работа');
    expect(child.parent, parent.id);
    expect(p.notes.length, 1);
    final jn = p.notes.first;
    expect(jn.title, 'План');
    expect(jn.parent, child.id);
    expect(jn.tags, ['важное']);
    expect(jn.body.contains('- [x] молоко'), true);
    expect(p.resources.length, 1);
    expect(utf8.decode(p.resources.values.first.bytes), 'hello');

    final blocks = Jex.toBlocks(jn.body, (rid) =>
        p.resources.containsKey(rid) ? Block(type: 'file', meta: {'att': 'x'}) : null);
    expect(blocks.any((b) => b.type == 'checklist' && b.items.length == 2), true);
    expect(blocks.any((b) => b.type == 'file'), true);
  });
}
