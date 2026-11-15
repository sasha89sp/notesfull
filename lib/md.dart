import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

part 'md_2.dart';
part 'md_3.dart';
part 'md_4.dart';


// ======================================================================
// Разбор Markdown (набор возможностей как в Joplin): заголовки, списки с
// вложенностью, чек-листы, цитаты, блоки кода, таблицы, линии, ссылки,
// изображения и вложения (:/id), **жирный**, *курсив*, ~~зачёркнутый~~,
// ==выделение==, ++подчёркнутый++, ~нижний~, ^верхний^, `код`.
// ======================================================================

abstract class MdBlock {}

class MdPara extends MdBlock {
  final String text;
  MdPara(this.text);
}

class MdHeading extends MdBlock {
  final int level;
  final String text;
  MdHeading(this.level, this.text);
}

class MdCode extends MdBlock {
  final String code;
  final String lang;
  MdCode(this.code, this.lang);
}

class MdQuote extends MdBlock {
  final List<MdBlock> children;
  MdQuote(this.children);
}

class MdHr extends MdBlock {}

class MdItem {
  final int level;
  final bool ordered;
  final int number;
  final bool? checked; // null — обычный пункт
  final String text;
  final int line; // номер строки в исходном тексте (для переключения галочки)
  MdItem(this.level, this.ordered, this.number, this.checked, this.text, this.line);
}

class MdList extends MdBlock {
  final List<MdItem> items;
  MdList(this.items);
}

class MdTable extends MdBlock {
  final List<String> head;
  final List<List<String>> rows;
  final List<TextAlign> align;
  MdTable(this.head, this.rows, this.align);
}

final RegExp _reFence = RegExp(r'^\s{0,3}(```+|~~~+)\s*([^`\s]*)\s*$');
final RegExp _reHeading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _reHr = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
final RegExp _reItem = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
final RegExp _reCheck = RegExp(r'^\[( |x|X)\]\s?(.*)$');
final RegExp _reTableSep = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');
final RegExp _reSetext1 = RegExp(r'^\s{0,3}=+\s*$');
final RegExp _reSetext2 = RegExp(r'^\s{0,3}-+\s*$');

bool _isBlank(String l) => l.trim().isEmpty;

bool _startsBlock(String l, String? next) {
  if (_reFence.hasMatch(l) || _reHeading.hasMatch(l) || _reHr.hasMatch(l)) return true;
  if (l.trimLeft().startsWith('>')) return true;
  if (_reItem.hasMatch(l)) return true;
  if (next != null && l.contains('|') && _reTableSep.hasMatch(next) && next.contains('-')) {
    return true;
  }
  return false;
}

List<String> _splitRow(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|') && !t.endsWith('\\|')) t = t.substring(0, t.length - 1);
  return t.split(RegExp(r'(?<!\\)\|')).map((c) => c.trim().replaceAll('\\|', '|')).toList();
}

/// Разбор строк в блоки. [offset] — номер первой строки в исходнике.
List<MdBlock> mdParse(List<String> lines, {int offset = 0}) {
  final out = <MdBlock>[];
  var i = 0;
  while (i < lines.length) {
    final l = lines[i];
    final next = i + 1 < lines.length ? lines[i + 1] : null;
    if (_isBlank(l)) {
      i++;
      continue;
    }
    // блок кода
    final f = _reFence.firstMatch(l);
    if (f != null) {
      final mark = f.group(1)!;
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith(mark.substring(0, 3))) {
        code.add(lines[i]);
        i++;
      }
      i++; // закрывающая ограда
      out.add(MdCode(code.join('\n'), f.group(2) ?? ''));
      continue;
    }
    final h = _reHeading.firstMatch(l);
    if (h != null) {
      out.add(MdHeading(h.group(1)!.length, h.group(2)!));
      i++;
      continue;
    }
    if (_reHr.hasMatch(l)) {
      out.add(MdHr());
      i++;
      continue;
    }
    // цитата
    if (l.trimLeft().startsWith('>')) {
      final inner = <String>[];
      while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
        var t = lines[i].trimLeft().substring(1);
        if (t.startsWith(' ')) t = t.substring(1);
        inner.add(t);
        i++;
      }
      out.add(MdQuote(mdParse(inner)));
      continue;
    }
    // таблица
    if (next != null && l.contains('|') && _reTableSep.hasMatch(next) && next.contains('-')) {
      final head = _splitRow(l);
      final align = _splitRow(next).map((c) {
        final left = c.startsWith(':');
        final right = c.endsWith(':');
        return left && right
            ? TextAlign.center
            : right
                ? TextAlign.right
                : TextAlign.left;
      }).toList();
      final rows = <List<String>>[];
      i += 2;
      while (i < lines.length && !_isBlank(lines[i]) && lines[i].contains('|')) {
        rows.add(_splitRow(lines[i]));
        i++;
      }
      out.add(MdTable(head, rows, align));
      continue;
    }
    // список
    if (_reItem.hasMatch(l)) {
      final items = <MdItem>[];
      final stack = <int>[];
      while (i < lines.length) {
        var cur = lines[i];
        var m = _reItem.firstMatch(cur);
        if (m == null) {
          // пустая строка внутри списка — список продолжается, если дальше снова пункт
          if (_isBlank(cur) &&
              i + 1 < lines.length &&
              _reItem.hasMatch(lines[i + 1])) {
            final nm = _reItem.firstMatch(lines[i + 1])!;
            final nIndent = nm.group(1)!.replaceAll('\t', '    ').length;
            final nOrd = RegExp(r'^\d').hasMatch(nm.group(2)!);
            // другой тип списка на том же уровне — это уже новый список
            if (items.isNotEmpty &&
                nOrd != items.first.ordered &&
                nIndent <= (stack.isEmpty ? 0 : stack.first)) {
              break;
            }
            i++;
            continue;
          }
          // продолжение текста пункта (с отступом)
          if (!_isBlank(cur) &&
              cur.startsWith(RegExp(r'\s+')) &&
              items.isNotEmpty &&
              !_startsBlock(cur, null)) {
            final last = items.removeLast();
            items.add(MdItem(last.level, last.ordered, last.number, last.checked,
                '${last.text}\n${cur.trim()}', last.line));
            i++;
            continue;
          }
          break;
        }
        final indent = m.group(1)!.replaceAll('\t', '    ').length;
        while (stack.isNotEmpty && stack.last > indent) {
          stack.removeLast();
        }
        if (stack.isEmpty || stack.last < indent) stack.add(indent);
        final marker = m.group(2)!;
        final ordered = RegExp(r'^\d').hasMatch(marker);
        var body = m.group(3)!;
        bool? checked;
        final c = _reCheck.firstMatch(body);
        if (c != null) {
          checked = c.group(1) != ' ';
          body = c.group(2) ?? '';
        }
        items.add(MdItem(stack.length - 1, ordered,
            ordered ? (int.tryParse(marker.replaceAll(RegExp(r'[^\d]'), '')) ?? 1) : 0,
            checked, body, offset + i));
        i++;
      }
      out.add(MdList(items));
      continue;
    }
    // абзац (и заголовки «подчёркиванием»)
    final para = <String>[l];
    i++;
    while (i < lines.length) {
      final cur = lines[i];
      if (_isBlank(cur)) break;
      if (_reSetext1.hasMatch(cur) || _reSetext2.hasMatch(cur)) {
        out.add(MdHeading(_reSetext1.hasMatch(cur) ? 1 : 2, para.join(' ')));
        para.clear();
        i++;
        break;
      }
      final nx = i + 1 < lines.length ? lines[i + 1] : null;
      if (_startsBlock(cur, nx)) break;
      para.add(cur);
      i++;
    }
    if (para.isNotEmpty) out.add(MdPara(para.join('\n')));
  }
  return out;
}

// ======================================================================
// Отображение
// ======================================================================

/// Документ Markdown. [store] нужен для вложений (`:/id`). [onChanged] включает
/// переключение чекбоксов нажатием: получает новый текст целиком.
class MdDoc extends StatefulWidget {
  final String text;
  final Store? store;
  final void Function(String newText)? onChanged;
  final void Function(String noteId)? onOpenNote;
  const MdDoc(this.text, {super.key, this.store, this.onChanged, this.onOpenNote});

  @override
  State<MdDoc> createState() => _MdDocState();
}