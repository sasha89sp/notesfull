import 'package:flutter/services.dart';

/// Операции форматирования Markdown над текстом и выделением (панель как в Joplin).
/// Все функции чистые: принимают значение поля, возвращают новое.
class MdOps {
  static TextSelection _sel(TextEditingValue v) {
    final s = v.selection;
    if (!s.isValid) return TextSelection.collapsed(offset: v.text.length);
    return s;
  }

  /// Обернуть выделение (**жирный**, *курсив*, `код`…). Повторное нажатие снимает разметку.
  static TextEditingValue wrap(TextEditingValue v, String left, String right,
      {String placeholder = 'текст'}) {
    final s = _sel(v);
    final t = v.text;
    final a = s.start, b = s.end;
    final sel = t.substring(a, b);
    // уже обёрнуто снаружи выделения
    if (a >= left.length &&
        t.length - b >= right.length &&
        t.substring(a - left.length, a) == left &&
        t.substring(b, b + right.length) == right) {
      final nt = t.substring(0, a - left.length) + sel + t.substring(b + right.length);
      return TextEditingValue(
          text: nt,
          selection: TextSelection(
              baseOffset: a - left.length, extentOffset: b - left.length));
    }
    // уже обёрнуто внутри выделения
    if (sel.length >= left.length + right.length &&
        sel.startsWith(left) &&
        sel.endsWith(right)) {
      final inner = sel.substring(left.length, sel.length - right.length);
      return TextEditingValue(
          text: t.substring(0, a) + inner + t.substring(b),
          selection: TextSelection(baseOffset: a, extentOffset: a + inner.length));
    }
    final body = sel.isEmpty ? placeholder : sel;
    final nt = t.substring(0, a) + left + body + right + t.substring(b);
    return TextEditingValue(
        text: nt,
        selection: TextSelection(
            baseOffset: a + left.length, extentOffset: a + left.length + body.length));
  }

  /// Вставить текст на место выделения; курсор — после вставки.
  static TextEditingValue insert(TextEditingValue v, String text) {
    final s = _sel(v);
    final nt = v.text.replaceRange(s.start, s.end, text);
    return TextEditingValue(
        text: nt, selection: TextSelection.collapsed(offset: s.start + text.length));
  }

  /// Диапазон строк, затронутых выделением: [от начала первой, до конца последней].
  static (int, int) _lineRange(String t, TextSelection s) {
    var a = s.start;
    var b = s.end;
    final st = t.lastIndexOf('\n', a > 0 ? a - 1 : 0);
    final from = a == 0 ? 0 : (st < 0 ? 0 : st + 1);
    if (b > a && b > 0 && t[b - 1] == '\n') b--; // выделение до конца строки с переводом
    final en = t.indexOf('\n', b);
    final to = en < 0 ? t.length : en;
    return (from, to);
  }

  static final RegExp _anyPrefix =
      RegExp(r'^(\s*)(#{1,6} |> |[-*+] \[[ xX]\] |[-*+] |\d+[.)] )');

  static String _strip(String line) => line.replaceFirst(_anyPrefix, r'$1');

  /// Префикс строк: маркер списка, цитата, чек-бокс. Если у всех строк уже есть такой
  /// префикс — он снимается; чужой префикс заменяется.
  static TextEditingValue linePrefix(TextEditingValue v, String kind) {
    final s = _sel(v);
    final t = v.text;
    final (from, to) = _lineRange(t, s);
    final lines = t.substring(from, to).split('\n');

    bool has(String l) {
      switch (kind) {
        case 'bullet':
          return RegExp(r'^\s*[-*+] (?!\[[ xX]\] )').hasMatch(l);
        case 'number':
          return RegExp(r'^\s*\d+[.)] ').hasMatch(l);
        case 'check':
          return RegExp(r'^\s*[-*+] \[[ xX]\] ').hasMatch(l);
        case 'quote':
          return l.startsWith('> ');
        default:
          return false;
      }
    }

    final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
    final allHave = nonEmpty.isNotEmpty && nonEmpty.every(has);
    var n = 1;
    final out = <String>[];
    for (final l in lines) {
      if (allHave) {
        out.add(_strip(l));
        continue;
      }
      final body = _strip(l);
      final ind = RegExp(r'^\s*').firstMatch(l)!.group(0)!;
      final core = body.substring(ind.length);
      switch (kind) {
        case 'bullet':
          out.add('$ind- $core');
          break;
        case 'number':
          out.add('$ind${n++}. $core');
          break;
        case 'check':
          out.add('$ind- [ ] $core');
          break;
        default:
          out.add('> $body');
      }
    }
    final joined = out.join('\n');
    return TextEditingValue(
      text: t.replaceRange(from, to, joined),
      selection: TextSelection(
          baseOffset: from, extentOffset: from + joined.length),
    );
  }

  /// Заголовок: цикл # → ## → ### → без заголовка. [level] задаёт уровень явно.
  static TextEditingValue heading(TextEditingValue v, {int? level}) {
    final s = _sel(v);
    final t = v.text;
    final (from, to) = _lineRange(t, s);
    final first = t.substring(from, to).split('\n').first;
    final m = RegExp(r'^(#{1,6}) ').firstMatch(first);
    final cur = m == null ? 0 : m.group(1)!.length;
    final next = level ?? (cur >= 3 ? 0 : cur + 1);
    final lines = t.substring(from, to).split('\n').map((l) {
      final core = l.replaceFirst(RegExp(r'^#{1,6} '), '');
      return next == 0 ? core : '${'#' * next} $core';
    }).join('\n');
    return TextEditingValue(
      text: t.replaceRange(from, to, lines),
      selection: TextSelection(baseOffset: from, extentOffset: from + lines.length),
    );
  }

  /// Блок кода: многострочное выделение → ограда ```, иначе `встроенный код`.
  static TextEditingValue code(TextEditingValue v) {
    final s = _sel(v);
    final sel = v.text.substring(s.start, s.end);
    if (sel.contains('\n')) {
      return wrap(v, '```\n', '\n```');
    }
    return wrap(v, '`', '`', placeholder: 'код');
  }

  /// Ссылка: выделенный текст становится названием, курсор встаёт на адрес.
  static TextEditingValue link(TextEditingValue v, {String url = 'https://'}) {
    final s = _sel(v);
    final label = s.isCollapsed ? 'ссылка' : v.text.substring(s.start, s.end);
    final text = '[$label]($url)';
    final nt = v.text.replaceRange(s.start, s.end, text);
    final urlStart = s.start + label.length + 3;
    return TextEditingValue(
        text: nt,
        selection: TextSelection(baseOffset: urlStart, extentOffset: urlStart + url.length));
  }

  /// Горизонтальная линия на отдельной строке.
  static TextEditingValue hr(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    final pre = s.start == 0 || t[s.start - 1] == '\n' ? '' : '\n';
    return insert(v, '$pre\n---\n\n');
  }

  /// Шаблон таблицы.
  static TextEditingValue table(TextEditingValue v, {int cols = 3, int rows = 2}) {
    final head = '| ${List.generate(cols, (i) => 'Колонка ${i + 1}').join(' | ')} |';
    final sep = '| ${List.generate(cols, (_) => '---').join(' | ')} |';
    final row = '| ${List.generate(cols, (_) => '   ').join(' | ')} |';
    final s = _sel(v);
    final pre = s.start == 0 || v.text[s.start - 1] == '\n' ? '' : '\n';
    return insert(v, '$pre\n$head\n$sep\n${List.filled(rows, row).join('\n')}\n\n');
  }

  /// Продолжение списка по Enter, как в Joplin: следующий пункт получает тот же маркер,
  /// пустой пункт завершает список. Используется в TextInputFormatter.
  static TextEditingValue? continueList(TextEditingValue old, TextEditingValue now) {
    if (!now.selection.isCollapsed || !old.selection.isCollapsed) return null;
    final pos = now.selection.baseOffset;
    if (pos < 1 || now.text.length != old.text.length + 1) return null;
    if (now.text[pos - 1] != '\n') return null;
    final lineEnd = pos - 1;
    final from = lineEnd == 0 ? 0 : now.text.lastIndexOf('\n', lineEnd - 1) + 1;
    final line = now.text.substring(from, lineEnd);
    final m = RegExp(r'^(\s*)([-*+] \[[ xX]\] |[-*+] |\d+[.)] |> )(.*)$').firstMatch(line);
    if (m == null) return null;
    final ind = m.group(1)!;
    var marker = m.group(2)!;
    final rest = m.group(3)!;
    if (rest.trim().isEmpty) {
      // пустой пункт: убираем маркер и выходим из списка
      final nt = now.text.replaceRange(from, pos, '');
      return TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: from));
    }
    final num = RegExp(r'^(\d+)([.)]) $').firstMatch(marker);
    if (num != null) {
      marker = '${int.parse(num.group(1)!) + 1}${num.group(2)} ';
    } else if (RegExp(r'^[-*+] \[[ xX]\] $').hasMatch(marker)) {
      marker = '${marker[0]} [ ] ';
    }
    final ins = '$ind$marker';
    final nt = now.text.replaceRange(pos, pos, ins);
    return TextEditingValue(
        text: nt, selection: TextSelection.collapsed(offset: pos + ins.length));
  }
}

/// Форматтер для TextField: продолжает списки по Enter.
class MdListFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return MdOps.continueList(oldValue, newValue) ?? newValue;
  }
}
