import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/import_parsers.dart';
import 'package:mysecure_notes/md5.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('asrbox_imp_'));
  tearDown(() async => tmp.delete(recursive: true));

  test('MD5: эталонные значения RFC 1321', () {
    expect(md5Hex([]), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(md5Hex('abc'.codeUnits), '900150983cd24fb0d6963f7d28e17f72');
    expect(md5Hex('The quick brown fox jumps over the lazy dog'.codeUnits), '9e107d9d372bb6826bd81d3542a419d6');
    expect(md5Hex('12345678901234567890123456789012345678901234567890123456789012345678901234567890'.codeUnits),
        '57edf4a22be3c955ac49da2e2107b67a');
  });

  test('Markdown (каталог): заголовок, вложенные папки, локальная картинка', () {
    Directory('${tmp.path}/sub').createSync();
    File('${tmp.path}/sub/pic.png').writeAsBytesSync([1, 2, 3]);
    File('${tmp.path}/sub/a.md').writeAsStringSync('# Заголовок\n\nтекст ![p](pic.png)\n');
    final r = impParse(ImpJob('md', [tmp.path], true));
    expect(r.length, 1);
    expect(r.first.title, 'Заголовок');
    expect(r.first.folder.length, 2);
    expect(r.first.folder.last, 'sub');
    expect(r.first.res.length, 1);
    expect(r.first.body, contains(':/${r.first.res.first.id}'));
  });

  test('Obsidian: теги, front matter, ссылки [[...]], вложение ![[...]]', () {
    File('${tmp.path}/pic.png').writeAsBytesSync([9, 9]);
    File('${tmp.path}/Идея.md').writeAsStringSync(
        '---\ntags: [работа, план]\n---\nСмотри [[Другая|ссылка]] и ![[pic.png]] #срочно\n');
    final r = impParse(ImpJob('obsidian', [tmp.path], true));
    expect(r.length, 1);
    expect(r.first.title, 'Идея');
    expect(r.first.tags, containsAll(['работа', 'план', 'срочно']));
    expect(r.first.body, contains('ссылка'));
    expect(r.first.body, isNot(contains('[[')));
    expect(r.first.res.length, 1);
  });

  test('ENEX: заголовок, теги, вложение по MD5-хэшу', () {
    final f = File('${tmp.path}/book.enex');
    f.writeAsStringSync('''<?xml version="1.0"?><en-export><note><title>Привет &amp; пока</title>
<content><![CDATA[<en-note><div>текст</div><en-media type="image/png" hash="5d41402abc4b2a76b9719d911017c592"/></en-note>]]></content>
<created>20210131T120000Z</created><tag>идея</tag>
<resource><data encoding="base64">aGVsbG8=</data><mime>image/png</mime><resource-attributes><file-name>h.png</file-name></resource-attributes></resource>
</note></en-export>''');
    final r = impParse(ImpJob('enex', [f.path], false));
    expect(r.length, 1);
    expect(r.first.title, 'Привет & пока');
    expect(r.first.tags, ['идея']);
    expect(r.first.folder, ['book']);
    expect(r.first.res.length, 1);
    expect(r.first.body, contains(':/${r.first.res.first.id}'));
    expect(r.first.created, DateTime.utc(2021, 1, 31, 12).millisecondsSinceEpoch);
  });

  test('TXT: имя файла — заголовок, переводы строк сохраняются', () {
    File('${tmp.path}/заметка.txt').writeAsStringSync('раз\nдва\n');
    final r = impParse(ImpJob('txt', ['${tmp.path}/заметка.txt'], false));
    expect(r.first.title, 'заметка');
    expect(r.first.body, contains('раз  \nдва'));
  });
}
