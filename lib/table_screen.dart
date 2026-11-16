// ▸ Редактор таблиц
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'formula.dart';
import 'models.dart';
import 'util.dart';
import 'widgets.dart';
import 'xlsx.dart';

part 'table_screen_2.dart';


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
  }}