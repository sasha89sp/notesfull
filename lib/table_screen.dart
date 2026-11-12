import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'formula.dart';
import 'models.dart';
import 'util.dart';
import 'widgets.dart';
import 'xlsx.dart';

const double _colW = 96;
const double _rowH = 40;
const double _hdrW = 44;

const List<int?> _palette = [
  null, 0xFFFFE5E5, 0xFFFFF2D9, 0xFFFFFBCC, 0xFFE0F5E0, 0xFFDDEEFF,
  0xFFEBE0FF, 0xFFE0E0E0, 0xFFFF3B30, 0xFFFF9500, 0xFF34C759, 0xFF007AFF,
  0xFFAF52DE, 0xFF000000, 0xFFFFFFFF,
];

/// Редактор таблицы. Режим просмотра по умолчанию, правка — по кнопке.
class TableScreen extends StatefulWidget {
  final Block block;
  final String title;
  final VoidCallback onChanged;
  const TableScreen(
      {super.key,
      required this.block,
      required this.title,
      required this.onChanged});
  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  late TableData t;
  bool edit = false;
  int sr = 0, sc = 0, er = 0, ec = 0; // выделение: якорь и конец
  bool _range = false;

  @override
  void initState() {
    super.initState();
    t = widget.block.table;
  }

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

  @override
  Widget build(BuildContext context) {
    final ev = Evaluator(t);
    final width = _hdrW + _colW * t.cols;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? 'Таблица' : widget.title),
        actions: [
          TextButton(
            onPressed: () => setState(() => edit = !edit),
            child: Text(edit ? 'Готово' : 'Править'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'x') _export();
              if (v == 'i') _import();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'x', child: Text('Экспорт в .xlsx')),
              PopupMenuItem(value: 'i', child: Text('Импорт из .xlsx')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(children: [
            _headerRow(),
            Expanded(
              child: ListView.builder(
                itemCount: t.rows,
                itemExtent: _rowH,
                itemBuilder: (_, r) => _row(ev, r),
              ),
            ),
          ]),
        ),
      ),
      bottomNavigationBar: !edit
          ? null
          : SafeArea(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _tool(Icons.edit_outlined, 'Ячейка', () => _editCell(sr, sc)),
                    _tool(Icons.select_all, _range ? 'Укажите конец…' : 'Диапазон',
                        () => setState(() => _range = true)),
                    _tool(Icons.format_color_fill, 'Фон', _bg),
                    _tool(Icons.format_color_text, 'Текст', _fg),
                    _tool(Icons.table_chart_outlined, 'Объединить', () {
                      t.mergeRange(sr, sc, er, ec);
                      _commit();
                    }),
                    _tool(Icons.call_split, 'Разъединить', () {
                      t.unmergeRange(sr, sc, er, ec);
                      _commit();
                    }),
                    _tool(Icons.add, 'Строка', () {
                      t.insertRow((sr < er ? er : sr) + 1);
                      _commit();
                    }),
                    _tool(Icons.add, 'Столбец', () {
                      t.insertCol((sc < ec ? ec : sc) + 1);
                      _commit();
                    }),
                    _tool(Icons.remove, 'Строка', () {
                      t.deleteRow(sr);
                      sr = er = sr.clamp(0, t.rows - 1).toInt();
                      _commit();
                    }),
                    _tool(Icons.remove, 'Столбец', () {
                      t.deleteCol(sc);
                      sc = ec = sc.clamp(0, t.cols - 1).toInt();
                      _commit();
                    }),
                  ],
                ),
              ),
            ),
    );
  }
}
