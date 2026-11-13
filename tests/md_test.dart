import 'package:flutter/painting.dart' show TextAlign;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysecure_notes/backup.dart';
import 'package:mysecure_notes/md.dart';
import 'package:mysecure_notes/md_ops.dart';
import 'package:mysecure_notes/models.dart';

TextEditingValue v(String t, int a, [int? b]) =>
    TextEditingValue(text: t, selection: TextSelection(baseOffset: a, extentOffset: b ?? a));

void main() {
  group('MdOps', () {
    test('жирный: обернуть и снять', () {
      var r = MdOps.wrap(v('привет мир', 0, 6), '**', '**');
      expect(r.text, '**привет** мир');
      r = MdOps.wrap(v(r.text, r.selection.start, r.selection.end), '**', '**');
      expect(r.text, 'привет мир');
    });
    test('пустое выделение вставляет заготовку', () {
      final r = MdOps.wrap(v('', 0), '*', '*');
      expect(r.text, '*текст*');
    });
    test('списки: включить, переключить, снять', () {
      var r = MdOps.linePrefix(v('a\nb', 0, 3), 'bullet');
      expect(r.text, '- a\n- b');
      r = MdOps.linePrefix(v(r.text, 0, r.text.length), 'number');
      expect(r.text, '1. a\n2. b');
      r = MdOps.linePrefix(v(r.text, 0, r.text.length), 'number');
      expect(r.text, 'a\nb');
      r = MdOps.linePrefix(v('x', 0), 'check');
      expect(r.text, '- [ ] x');
    });
    test('заголовок по кругу', () {
      var r = MdOps.heading(v('текст', 0));
      expect(r.text, '# текст');
      r = MdOps.heading(v(r.text, 0));
      expect(r.text, '## текст');
      r = MdOps.heading(v('## текст', 0), level: 0);
      expect(r.text, 'текст');
    });
    test('Enter продолжает список и закрывает пустой пункт', () {
      final old = v('- a', 3);
      final now = v('- a\n', 4);
      final r = MdOps.continueList(old, now)!;
      expect(r.text, '- a\n- ');
      final r2 = MdOps.continueList(v('- a\n- ', 6), v('- a\n- \n', 7))!;
      expect(r2.text, '- a\n');
      final n = MdOps.continueList(v('1. a', 4), v('1. a\n', 5))!;
      expect(n.text, '1. a\n2. ');
      final c = MdOps.continueList(v('- [x] a', 7), v('- [x] a\n', 8))!;
      expect(c.text, '- [x] a\n- [ ] ');
    });
    test('ссылка', () {
      final r = MdOps.link(v('сайт', 0, 4), url: 'https://a.b');
      expect(r.text, '[сайт](https://a.b)');
    });
  });

  group('mdParse', () {
    test('заголовки, списки, чекбоксы, код, таблица, цитата', () {
      const src = '''# Заголовок
Текст **жирный**

- один
  - вложенный
- [x] сделано
- [ ] нет

1. раз
2. два

> цитата

```dart
код
```

| A | B |
|---|:-:|
| 1 | 2 |

---''';
      final b = mdParse(src.split('\n'));
      expect(b.whereType<MdHeading>().single.level, 1);
      final list = b.whereType<MdList>().first;
      expect(list.items[1].level, 1);
      expect(list.items[2].checked, true);
      expect(list.items[3].checked, false);
      expect(b.whereType<MdList>().last.items.first.ordered, true);
      expect(b.whereType<MdQuote>().length, 1);
      expect(b.whereType<MdCode>().single.code, 'код');
      final t = b.whereType<MdTable>().single;
      expect(t.head, ['A', 'B']);
      expect(t.rows.single, ['1', '2']);
      expect(t.align[1], TextAlign.center);
      expect(b.whereType<MdHr>().length, 1);
    });
    test('номер строки чекбокса указывает в исходный текст', () {
      final lines = 'a\n\n- [ ] x\n- [x] y'.split('\n');
      final l = mdParse(lines).whereType<MdList>().single;
      expect(lines[l.items[0].line], '- [ ] x');
      expect(lines[l.items[1].line], '- [x] y');
    });
  });

  group('Joplin', () {
    test('HTML → Markdown', () {
      final md = Jex.htmlToMd('<h2>Т</h2><p>a <b>b</b> <a href="http://x">l</a></p><ul><li>1</li><li>2</li></ul>');
      expect(md, contains('## Т'));
      expect(md, contains('**b**'));
      expect(md, contains('[l](http://x)'));
      expect(md, contains('- 1'));
    });

    test('экспорт → разбор: текст, вложение в тексте и теги сохраняются', () {
      final n = Note.create('Аня', 'p1', 'personal')
        ..title = 'Заметка'
        ..tags = ['тег']
        ..blocks = [
          Block(type: 'text', content: '# H\n\n- [x] ok\n\n![pic](:/abc123)\n\n| a | b |\n|---|---|\n| 1 | 2 |'),
        ];
      final bytes = Jex.export([], [n], {'abc123': [1, 2, 3]});
      final p = Jex.parse(bytes);
      expect(p.notes.single.title, 'Заметка');
      expect(p.notes.single.tags, ['тег']);
      expect(p.resources.length, 1);
      final rid = p.resources.keys.single;
      expect(p.notes.single.body, contains('![pic](:/$rid)'));
      expect(p.notes.single.body, contains('| a | b |'));
      expect(p.resources[rid]!.bytes, [1, 2, 3]);
    });

    test('вложения из текста учитываются как вложения заметки', () {
      final n = Note.create('a', 'p', 'personal')
        ..blocks = [Block(type: 'text', content: 'см. [файл](:/f1) и ![](:/i2)')];
      expect(n.attachmentIds(), {'f1', 'i2'});
    });
  });
}
