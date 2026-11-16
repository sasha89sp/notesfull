// ▸ Строчные операции меню «Правка» (как в Joplin): удалить/дублировать/переместить
import 'package:flutter/services.dart';
import 'md_ops.dart';

/// Строчные операции меню «Правка» (как в Joplin): удалить/дублировать/переместить
/// строку, комментарий, сортировка, отступы. Чистые функции над значением поля.
class MdLines {
  static (int, int, String) _blk(TextEditingValue v) {
    final s = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final (a, b) = MdOps.lineRange(v.text, s);
    return (a, b, v.text.substring(a, b));
  }

  static TextEditingValue _sel(String text, int a, int b) => TextEditingValue(
      text: text, selection: TextSelection(baseOffset: a, extentOffset: b));

  static TextEditingValue deleteLine(TextEditingValue v) {
    final (a, b, _) = _blk(v);
    final t = v.text;
    final end = b < t.length ? b + 1 : b; // забрать перевод строки
    var start = a;
    if (end == b && a > 0) start = a - 1; // последняя строка: убрать предыдущий перевод
    final nt = t.replaceRange(start, end, '');
    return TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: start.clamp(0, nt.length)));
  }

  static TextEditingValue duplicateLine(TextEditingValue v) {
    final (_, b, body) = _blk(v);
    final nt = v.text.replaceRange(b, b, '\n$body');
    return _sel(nt, b + 1, b + 1 + body.length);
  }

  static TextEditingValue toggleComment(TextEditingValue v) {
    final (a, b, body) = _blk(v);
    final lines = body.split('\n');
    final all = lines.every((l) => l.trim().startsWith('<!--') && l.trim().endsWith('-->'));
    final out = lines.map((l) {
      if (all) {
        return l.replaceFirstMapped(RegExp(r'<!--\s?(.*?)\s?-->'), (m) => m.group(1) ?? '');
      }
      return '<!-- $l -->';
    }).join('\n');
    return _sel(v.text.replaceRange(a, b, out), a, a + out.length);
  }

  static TextEditingValue sortLines(TextEditingValue v) {
    final s = v.selection;
    if (!s.isValid || s.isCollapsed) return v; // как в Joplin: только для выделенного
    final (a, b, body) = _blk(v);
    final lines = body.split('\n')..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));
    final out = lines.join('\n');
    return _sel(v.text.replaceRange(a, b, out), a, a + out.length);
  }

  static const String _tab = '    ';

  static TextEditingValue indent(TextEditingValue v) {
    final (a, b, body) = _blk(v);
    final out = body.split('\n').map((l) => _tab + l).join('\n');
    return _sel(v.text.replaceRange(a, b, out), a, a + out.length);
  }

  static TextEditingValue outdent(TextEditingValue v) {
    final (a, b, body) = _blk(v);
    final out = body
        .split('\n')
        .map((l) => l.startsWith('\t')
            ? l.substring(1)
            : l.replaceFirst(RegExp(r'^ {1,4}'), ''))
        .join('\n');
    return _sel(v.text.replaceRange(a, b, out), a, a + out.length);
  }

  /// Переместить выделенные строки вверх (up=true) или вниз.
  static TextEditingValue move(TextEditingValue v, {required bool up}) {
    final (a, b, body) = _blk(v);
    final t = v.text;
    if (up) {
      if (a == 0) return v;
      final (pa, pb) = MdOps.lineRange(t, TextSelection.collapsed(offset: a - 1));
      final prev = t.substring(pa, pb);
      final nt = t.replaceRange(pa, b, '$body\n$prev');
      return _sel(nt, pa, pa + body.length);
    }
    if (b >= t.length) return v;
    final (na, nb) = MdOps.lineRange(t, TextSelection.collapsed(offset: b + 1));
    final next = t.substring(na, nb);
    final nt = t.replaceRange(a, nb, '$next\n$body');
    final st = a + next.length + 1;
    return _sel(nt, st, st + body.length);
  }
}
