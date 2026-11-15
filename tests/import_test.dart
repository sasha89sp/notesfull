import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/import_parsers.dart';
import 'package:mysecure_notes/ics.dart';
import 'package:mysecure_notes/md5.dart';
import 'package:mysecure_notes/models.dart';
import 'package:mysecure_notes/pass_io.dart';

void main() {
  passwordIoTests();
  icsRawTests();
  icsRruleTests();
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

void passwordIoTests() {
  group('PassIO', () {
    test('KeePass XML: запись с историей не теряется, группы -> папки', () {
      const xml = '<?xml version="1.0"?><KeePassFile><Root><Group><Name>Database</Name>'
          '<Group><Name>Почта</Name>'
          '<Entry><String><Key>Title</Key><Value>Gmail</Value></String>'
          '<String><Key>UserName</Key><Value>me</Value></String>'
          '<String><Key>Password</Key><Value ProtectInMemory="True">p&amp;1</Value></String>'
          '<History><Entry><String><Key>Title</Key><Value>Old</Value></String></Entry></History></Entry>'
          '</Group></Group></Root></KeePassFile>';
      final l = PassIO.import('x.xml', xml);
      expect(l.length, 1);
      expect(l.first.title, 'Gmail');
      expect(l.first.password, 'p&1');
      expect(l.first.folder, 'Почта');
    });
    test('Bitwarden JSON: экспорт -> импорт', () {
      final e = PassEntry.create()
        ..title = 'Site'
        ..username = 'u'
        ..password = 'pw'
        ..url = 'https://a.b'
        ..folder = 'Work';
      final back = PassIO.import('b.json', PassIO.exportBitwardenJson([e]));
      expect(back.single.title, 'Site');
      expect(back.single.folder, 'Work');
      expect(back.single.password, 'pw');
    });
    test('Bitwarden CSV и KeePass: экспорт -> импорт', () {
      final e = PassEntry.create()
        ..title = 'A'
        ..password = 'x,"y"'
        ..url = 'u';
      expect(PassIO.import('b.csv', PassIO.exportBitwardenCsv([e])).single.password, 'x,"y"');
      expect(PassIO.import('k.xml', PassIO.exportKeepassXml([e])).single.password, 'x,"y"');
    });
  });
}

void icsRawTests() {
  group('IcsRaw', () {
    const src = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a1\r\nDTSTART;VALUE=DATE:20261115\r\n'
        'DTEND;VALUE=DATE:20261116\r\nSUMMARY:День\\, рождения\r\nX-CUSTOM:1\r\n'
        'BEGIN:VALARM\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
    test('разбор и сборка сохраняют свойства', () {
      final l = IcsRaw.parse(src);
      expect(l.length, 1);
      expect(IcsRaw.isAllDay(l.first), isTrue);
      expect(IcsRaw.text(IcsRaw.get(l.first, 'SUMMARY')!), 'День, рождения');
      expect(IcsRaw.get(l.first, 'X-CUSTOM'), '1');
      final back = IcsRaw.parse(IcsRaw.build(l));
      expect(back.first['UID'], 'a1');
      expect(IcsRaw.start(back.first)!.day, 15);
    });
    test('в событие календаря', () {
      final e = IcsRaw.toCal(IcsRaw.parse(src).first, calId: 'c1')!;
      expect(e.allDay, isTrue);
      expect(e.calId, 'c1');
      expect(e.title, 'День, рождения');
    });
  });
}

void icsRruleTests() {
  test('RRULE: еженедельно по ПН и СР, COUNT и EXDATE', () {
    final m = {
      'DTSTART': '20261102T090000',
      'RRULE': 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4',
      'EXDATE': '20261104T090000',
    };
    final l = IcsRaw.occurrences(m, DateTime(2026, 11, 1), DateTime(2027, 1, 1));
    // 2.11 (пн), 4.11 (ср, исключён), 9.11 (пн), 11.11 (ср) — всего 4 вхождения, одно исключено
    expect(l.map((d) => d.day).toList(), [2, 9, 11]);
  });
  test('RRULE: ежемесячно и ежегодно', () {
    final mo = IcsRaw.occurrences({'DTSTART': '20260115T100000', 'RRULE': 'FREQ=MONTHLY;COUNT=3'}, DateTime(2026, 1, 1), DateTime(2027, 1, 1));
    expect(mo.map((d) => d.month).toList(), [1, 2, 3]);
    final yr = IcsRaw.occurrences({'DTSTART': '20260301T100000', 'RRULE': 'FREQ=YEARLY'}, DateTime(2026, 1, 1), DateTime(2028, 12, 31));
    expect(yr.map((d) => d.year).toList(), [2026, 2027, 2028]);
  });
  test('VALARM сохраняется при пересборке', () {
    const src = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:z\r\nDTSTART:20261115T100000Z\r\nBEGIN:VALARM\r\nTRIGGER:-PT10M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
    final out = IcsRaw.build(IcsRaw.parse(src));
    expect(out.contains('BEGIN:VALARM'), isTrue);
    expect(out.contains('TRIGGER:-PT10M'), isTrue);
  });
}
