// ▸ Часть table_screen.dart: Редактор таблиц  [содержит: _ExtTableScreenState1]
part of 'table_screen.dart';

extension _ExtTableScreenState1 on _TableScreenState {

  void _commit() {
    widget.block.table = t;
    widget.onChanged();
    setState(() {});
  }

  void _select(int r, int c) {
    setState(() {
      if (_range) {
        er = r;
        ec = c;
        _range = false;
      } else {
        sr = er = r;
        sc = ec = c;
      }
    });
  }

  bool _inSel(int r, int c) =>
      r >= (sr < er ? sr : er) &&
      r <= (sr < er ? er : sr) &&
      c >= (sc < ec ? sc : ec) &&
      c <= (sc < ec ? ec : sc);

  Future<void> _editCell(int r, int c) async {
    final m = t.mergeAt(r, c);
    final ar = m?.r ?? r, ac = m?.c ?? c;
    final ctl = TextEditingController(text: t.cells[ar][ac].v);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ячейка ${colName(ac)}${ar + 1}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
              hintText: 'Текст или формула: =SUM(A1:A5), =B2*C2'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Готово')),
        ],
      ),
    );
    if (ok == true) {
      t.cells[ar][ac].v = ctl.text;
      _commit();
    }
    ctl.dispose();
  }

  Future<int?> _pickColor() {
    return showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Цвет'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in _palette)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, c ?? -1),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c == null ? null : Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: Pal.border(ctx)),
                  ),
                  child: c == null ? const Icon(Icons.block, size: 18) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _forSel(void Function(Cell) f) {
    final r1 = sr < er ? sr : er, r2 = sr < er ? er : sr;
    final c1 = sc < ec ? sc : ec, c2 = sc < ec ? ec : sc;
    for (var r = r1; r <= r2; r++) {
      for (var c = c1; c <= c2; c++) {
        f(t.cells[r][c]);
      }
    }
    _commit();
  }

  Future<void> _bg() async {
    final c = await _pickColor();
    if (c == null) return;
    _forSel((x) => x.bg = c == -1 ? null : c);
  }

  Future<void> _fg() async {
    final c = await _pickColor();
    if (c == null) return;
    _forSel((x) => x.fg = c == -1 ? null : c);
  }

  Future<void> _export() async {
    final bytes = Xlsx.export(t, widget.title);
    final name = '${widget.title.isEmpty ? 'table' : widget.title}.xlsx';
    final ok = await saveBytes(name, bytes);
    if (ok && mounted) toast(context, 'Файл сохранён');
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    try {
      t = Xlsx.import(r.files.first.bytes!);
      sr = sc = er = ec = 0;
      _commit();
    } catch (e) {
      if (mounted) toast(context, 'Не удалось импортировать: $e');
    }
  }

  Widget _headerRow() {
    return Row(children: [
      Container(
        width: _hdrW,
        height: 28,
        decoration: BoxDecoration(
            color: Pal.card3(context),
            border: Border.all(color: Pal.border(context), width: 0.5)),
      ),
      for (var c = 0; c < t.cols; c++)
        Container(
          width: _colW,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Pal.card3(context),
              border: Border.all(color: Pal.border(context), width: 0.5)),
          child: Text(colName(c),
              style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
        ),
    ]);
  }

  Widget _cell(Evaluator ev, int r, int c, double w, Merge? m) {
    final cell = t.cells[r][c];
    final shown = ev.display(r, c);
    final sel = _inSel(r, c);
    final bg = cell.bg != null ? Color(cell.bg!) : null;
    final fg = cell.fg != null ? Color(cell.fg!) : null;
    final isNum = double.tryParse(shown.replaceAll(',', '.')) != null;
    return GestureDetector(
      onTap: () {
        _select(r, c);
        if (edit) _editCell(r, c);
      },
      child: Container(
        width: w,
        height: _rowH,
        alignment: isNum ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: sel ? Theme.of(context).colorScheme.primary.withOpacity(0.18) : bg,
          border: Border.all(
              color: sel
                  ? Theme.of(context).colorScheme.primary
                  : Pal.border(context),
              width: sel ? 1.2 : 0.5),
        ),
        child: Text(shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: shown.startsWith('#') ? Pal.error(context) : fg,
                fontSize: 14)),
      ),
    );
  }

  Widget _row(Evaluator ev, int r) {
    final kids = <Widget>[
      Container(
        width: _hdrW,
        height: _rowH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Pal.card3(context),
            border: Border.all(color: Pal.border(context), width: 0.5)),
        child: Text('${r + 1}',
            style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
      ),
    ];
    var c = 0;
    while (c < t.cols) {
      final m = t.mergeAt(r, c);
      if (m != null && m.r == r && m.c == c) {
        kids.add(_cell(ev, r, c, _colW * m.cs, m));
        c += m.cs;
      } else if (m != null) {
        // продолжение объединённой области в нижних строках
        final a = t.cells[m.r][m.c];
        kids.add(GestureDetector(
          onTap: () {
            _select(m.r, m.c);
            if (edit) _editCell(m.r, m.c);
          },
          child: Container(
            width: _colW,
            height: _rowH,
            decoration: BoxDecoration(
              color: a.bg != null ? Color(a.bg!) : null,
              border: Border(
                left: BorderSide(color: Pal.border(context), width: 0.5),
                right: BorderSide(color: Pal.border(context), width: 0.5),
                bottom: r == m.r + m.rs - 1
                    ? BorderSide(color: Pal.border(context), width: 0.5)
                    : BorderSide.none,
              ),
            ),
          ),
        ));
        c++;
      } else {
        kids.add(_cell(ev, r, c, _colW, null));
        c++;
      }
    }
    return Row(children: kids);
  }

  Widget _tool(IconData icon, String label, VoidCallback f) => TextButton.icon(
        onPressed: f,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
