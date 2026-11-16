// ▸ Часть md.dart: Разбор Markdown в блоки и отображение (MdDoc)  [содержит: _ExtMdDocState1, _MdImage]
part of 'md.dart';

extension _ExtMdDocState1 on _MdDocState {

  void _disposeRecs() {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
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

  List<InlineSpan> _spans(String s, TextStyle st) {
    final spans = <InlineSpan>[];
    var last = 0;
    final link = Theme.of(context).colorScheme.primary;
    for (final m in _MdDocState._inl.allMatches(s)) {
      if (m.start > last) spans.addAll(_plain(s.substring(last, m.start), st));
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
    if (last < s.length) spans.addAll(_plain(s.substring(last), st));
    return spans;
  }

  /// Обычный текст: #теги — янтарные, [[ссылки]] — индиго.
  List<InlineSpan> _plain(String t, TextStyle st) {
    if (!t.contains('#') && !t.contains('[[')) return [TextSpan(text: t, style: st)];
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _MdDocState._tagRe.allMatches(t)) {
      final tag = m.group(2);
      final start = tag != null ? m.start + m.group(1)!.length : m.start;
      if (start > last) out.add(TextSpan(text: t.substring(last, start), style: st));
      if (tag != null) {
        out.add(TextSpan(
            text: tag, style: st.copyWith(color: Pal.tagFg(context), backgroundColor: Pal.tagBg(context))));
      } else {
        final raw = m.group(3)!;
        out.add(TextSpan(
            text: raw.substring(2, raw.length - 2),
            style: st.copyWith(color: Pal.accent(context), backgroundColor: Pal.linkBg(context))));
      }
      last = m.end;
    }
    if (last < t.length) out.add(TextSpan(text: t.substring(last), style: st));
    return out;
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
            decoration: TextDecoration.lineThrough, color: Pal.muted(context))
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