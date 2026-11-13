import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

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

class _MdDocState extends State<MdDoc> {
  final List<TapGestureRecognizer> _recs = [];

  void _disposeRecs() {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
  }

  @override
  void dispose() {
    _disposeRecs();
    super.dispose();
  }

  Future<void> _open(String url, String label) async {
    final st = widget.store;
    if (url.startsWith(':/')) {
      final id = url.substring(2).split(RegExp(r'[#\s]')).first;
      if (st != null && st.hasAttachment(id)) {
        final b = await st.readAttachment(id);
        if (b != null && mounted) {
          final ok = await saveBytes(label.isEmpty ? id : label, b);
          if (ok && mounted) toast(context, 'Файл сохранён');
        }
        return;
      }
      widget.onOpenNote?.call(id);
      return;
    }
    final u = Uri.tryParse(url);
    if (u != null && (u.scheme == 'http' || u.scheme == 'https' || u.scheme == 'mailto')) {
      try {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) toast(context, 'Не удалось открыть ссылку');
      }
    }
  }

  static final RegExp _inl = RegExp(
    r'\\([\\`*_{}\[\]()#+\-.!~=^|<>])' // 1 экранирование
    r'|!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)' // 2 alt, 3 src
    r'|\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)' // 4 текст, 5 адрес
    r'|`([^`]+)`' // 6 код
    r'|\*\*(.+?)\*\*' // 7 жирный
    r'|__(.+?)__' // 8 жирный
    r'|~~(.+?)~~' // 9 зачёркнутый
    r'|==(.+?)==' // 10 выделение
    r'|\+\+(.+?)\+\+' // 11 подчёркнутый
    r'|\*([^*\s][^*]*?)\*' // 12 курсив
    r'|(?<![A-Za-z0-9_])_([^_\s][^_]*?)_(?![A-Za-z0-9_])' // 13 курсив
    r'|~([^~\s]+)~' // 14 нижний индекс
    r'|\^([^\^\s]+)\^' // 15 верхний индекс
    r'|<(https?://[^>\s]+)>' // 16 ссылка в <>
    r'|(https?://[^\s<>()]+)' // 17 голая ссылка
    r'|(<br\s*/?>)', // 18 перенос
  );

  List<InlineSpan> _spans(String s, TextStyle st) {
    final spans = <InlineSpan>[];
    var last = 0;
    final link = Theme.of(context).colorScheme.primary;
    for (final m in _inl.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start), style: st));
      last = m.end;
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: st));
      } else if (m.group(3) != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _MdImage(src: m.group(3)!, alt: m.group(2) ?? '', store: widget.store),
        ));
      } else if (m.group(5) != null) {
        final url = m.group(5)!;
        final label = m.group(4) ?? '';
        final rec = TapGestureRecognizer()..onTap = () => _open(url, label);
        _recs.add(rec);
        spans.add(TextSpan(
          children: _spans(label.isEmpty ? url : label, st.copyWith(
              color: link, decoration: TextDecoration.underline, decorationColor: link)),
          recognizer: rec,
        ));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(
            text: m.group(6),
            style: st.copyWith(
                fontFamily: 'monospace',
                fontSize: (st.fontSize ?? 17) * 0.9,
                backgroundColor: const Color(0x33888888))));
      } else if (m.group(7) != null || m.group(8) != null) {
        spans.add(TextSpan(
            children: _spans(m.group(7) ?? m.group(8)!, st.copyWith(fontWeight: FontWeight.bold))));
      } else if (m.group(9) != null) {
        spans.add(TextSpan(
            children: _spans(m.group(9)!, st.copyWith(decoration: TextDecoration.lineThrough))));
      } else if (m.group(10) != null) {
        spans.add(TextSpan(
            children: _spans(m.group(10)!, st.copyWith(backgroundColor: const Color(0x66FFEB3B)))));
      } else if (m.group(11) != null) {
        spans.add(TextSpan(
            children: _spans(m.group(11)!, st.copyWith(decoration: TextDecoration.underline))));
      } else if (m.group(12) != null || m.group(13) != null) {
        spans.add(TextSpan(
            children: _spans(m.group(12) ?? m.group(13)!, st.copyWith(fontStyle: FontStyle.italic))));
      } else if (m.group(14) != null) {
        spans.add(TextSpan(text: m.group(14), style: st.copyWith(fontSize: (st.fontSize ?? 17) * 0.75)));
      } else if (m.group(15) != null) {
        spans.add(TextSpan(text: m.group(15), style: st.copyWith(fontSize: (st.fontSize ?? 17) * 0.75)));
      } else if (m.group(16) != null || m.group(17) != null) {
        final url = m.group(16) ?? m.group(17)!;
        final rec = TapGestureRecognizer()..onTap = () => _open(url, '');
        _recs.add(rec);
        spans.add(TextSpan(
            text: url,
            style: st.copyWith(
                color: link, decoration: TextDecoration.underline, decorationColor: link),
            recognizer: rec));
      } else {
        spans.add(TextSpan(text: '\n', style: st));
      }
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last), style: st));
    return spans;
  }

  void _toggle(MdItem it) {
    final cb = widget.onChanged;
    if (cb == null) return;
    final lines = widget.text.split('\n');
    if (it.line < 0 || it.line >= lines.length) return;
    final l = lines[it.line];
    final m = RegExp(r'\[( |x|X)\]').firstMatch(l);
    if (m == null) return;
    lines[it.line] =
        l.replaceRange(m.start, m.end, it.checked == true ? '[ ]' : '[x]');
    cb(lines.join('\n'));
  }

  Widget _block(MdBlock b, TextStyle base, {bool top = false, bool interactive = true}) {
    final sec = Pal.secondary(context);
    if (b is MdHeading) {
      const sizes = [28.0, 24.0, 21.0, 19.0, 17.0, 16.0];
      final st = base.copyWith(
          fontSize: sizes[b.level - 1],
          fontWeight: FontWeight.w700,
          color: b.level == 6 ? sec : null);
      return Padding(
        padding: EdgeInsets.only(top: top ? 0 : 10, bottom: 4),
        child: Text.rich(TextSpan(children: _spans(b.text, st))),
      );
    }
    if (b is MdPara) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(TextSpan(children: _spans(b.text, base))),
      );
    }
    if (b is MdHr) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1));
    }
    if (b is MdCode) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Pal.dark(context) ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Pal.border(context), width: 0.5),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(b.code,
              style: base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 17) * 0.85)),
        ),
      );
    }
    if (b is MdQuote) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
            border: Border(left: BorderSide(color: sec.withOpacity(0.6), width: 3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in b.children)
              _block(c, base.copyWith(color: sec), top: true, interactive: false),
          ],
        ),
      );
    }
    if (b is MdList) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final it in b.items) _item(it, base, interactive)],
        ),
      );
    }
    if (b is MdTable) return _table(b, base);
    return const SizedBox.shrink();
  }

  Widget _item(MdItem it, TextStyle base, bool interactive) {
    final done = it.checked == true;
    final st = done
        ? base.copyWith(
            decoration: TextDecoration.lineThrough, color: Pal.secondary(context))
        : base;
    Widget lead;
    if (it.checked != null) {
      lead = SizedBox(
        width: 28,
        height: 26,
        child: Checkbox(
          visualDensity: VisualDensity.compact,
          value: done,
          onChanged: interactive && widget.onChanged != null ? (_) => _toggle(it) : null,
        ),
      );
    } else if (it.ordered) {
      lead = SizedBox(width: 28, child: Text('${it.number}.', style: base));
    } else {
      final bullets = ['•', '◦', '▪'];
      lead = SizedBox(width: 20, child: Text(bullets[it.level % 3], style: base));
    }
    return Padding(
      padding: EdgeInsets.only(left: 6.0 + it.level * 20, top: 1, bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
          Expanded(child: Text.rich(TextSpan(children: _spans(it.text, st)))),
        ],
      ),
    );
  }

  Widget _table(MdTable t, TextStyle base) {
    final cols = t.head.length;
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
          decoration: head ? const BoxDecoration(color: Color(0x1A888888)) : null,
          children: [
            for (var c = 0; c < cols; c++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text.rich(
                  TextSpan(
                      children: _spans(c < cells.length ? cells[c] : '',
                          head ? base.copyWith(fontWeight: FontWeight.w700) : base)),
                  textAlign: c < t.align.length ? t.align[c] : TextAlign.left,
                ),
              ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: Pal.border(context), width: 0.7),
          children: [row(t.head, head: true), for (final r in t.rows) row(r)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecs();
    final base = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 17))
        .copyWith(fontSize: 17, height: 1.4);
    final blocks = mdParse(widget.text.replaceAll('\r\n', '\n').split('\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) _block(blocks[i], base, top: i == 0),
      ],
    );
  }
}

/// Картинка из вложения (`:/id`) или из интернета.
class _MdImage extends StatefulWidget {
  final String src;
  final String alt;
  final Store? store;
  const _MdImage({required this.src, required this.alt, this.store});

  @override
  State<_MdImage> createState() => _MdImageState();
}

class _MdImageState extends State<_MdImage> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = widget.src;
    if (s.startsWith(':/') && widget.store != null) {
      final id = s.substring(2).split(RegExp(r'[#\s]')).first;
      _bytes = await widget.store!.readAttachment(id);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.src;
    final w = MediaQuery.of(context).size.width - 56;
    if (s.startsWith('http')) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: 420),
        child: Image.network(s,
            errorBuilder: (_, __, ___) => Text('[изображение: ${widget.alt}]')),
      );
    }
    if (!_loaded) return const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2));
    if (_bytes == null) {
      return Text('[нет вложения: ${widget.alt.isEmpty ? s : widget.alt}]',
          style: TextStyle(color: Pal.secondary(context)));
    }
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(child: Image.memory(_bytes!)),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: 420),
        child: Image.memory(_bytes!,
            errorBuilder: (_, __, ___) => Text('[не изображение: ${widget.alt}]')),
      ),
    );
  }
}
