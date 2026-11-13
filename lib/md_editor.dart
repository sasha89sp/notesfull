import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'md.dart';
import 'md_ops.dart';
import 'media.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Текстовый блок с Markdown, как в Joplin: панель форматирования при редактировании
/// и красиво отрисованный текст в покое (нажатие — вернуться к правке).
class MdTextBlock extends StatefulWidget {
  final Store store;
  final Block block;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final void Function(String noteId)? onOpenNote;

  const MdTextBlock({
    super.key,
    required this.store,
    required this.block,
    required this.controller,
    required this.onChanged,
    this.onOpenNote,
  });

  @override
  State<MdTextBlock> createState() => _MdTextBlockState();
}

class _MdTextBlockState extends State<MdTextBlock> {
  final FocusNode _focus = FocusNode();
  final UndoHistoryController _undo = UndoHistoryController();
  bool _editing = false;
  bool _busy = false; // открыт диалог: потеря фокуса не закрывает правку

  TextEditingController get c => widget.controller;
  Block get b => widget.block;

  @override
  void initState() {
    super.initState();
    _editing = b.content.trim().isEmpty;
    _focus.addListener(() {
      if (!_focus.hasFocus && !_busy && mounted && c.text.trim().isNotEmpty) {
        setState(() => _editing = false);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _undo.dispose();
    super.dispose();
  }

  void _apply(TextEditingValue v) {
    c.value = v;
    b.content = v.text;
    widget.onChanged();
    setState(() {});
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _op(TextEditingValue Function(TextEditingValue) f) => _apply(f(c.value));

  Future<void> _link() async {
    final sel = c.selection;
    final t = sel.isValid && !sel.isCollapsed ? c.text.substring(sel.start, sel.end) : '';
    final ctl = TextEditingController(text: 'https://');
    _busy = true;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.isEmpty ? 'Ссылка' : 'Ссылка для «$t»'),
        content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Адрес')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Вставить')),
        ],
      ),
    );
    ctl.dispose();
    _busy = false;
    if (url == null || url.isEmpty) {
      _focus.requestFocus();
      return;
    }
    _apply(MdOps.link(c.value, url: url));
  }

  Future<void> _attach(bool image) async {
    _busy = true;
    try {
      final blk = image
          ? await pickImageBlock(context, widget.store)
          : await pickFileBlock(context, widget.store);
      if (blk == null || blk.att == null) return;
      final name = (blk.meta['name'] ?? (image ? 'image' : 'file')).toString();
      final ref = image ? '![$name](:/${blk.att})' : '[$name](:/${blk.att})';
      _apply(MdOps.insert(c.value, '\n$ref\n'));
    } finally {
      _busy = false;
      if (mounted) _focus.requestFocus();
    }
  }

  void _headingMenu() {
    _busy = true;
    showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 6; i++)
            ListTile(
              dense: true,
              title: Text('Заголовок $i',
                  style: TextStyle(fontSize: 26 - i * 2.0, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, i),
            ),
          ListTile(dense: true, title: const Text('Обычный текст'), onTap: () => Navigator.pop(ctx, 0)),
        ]),
      ),
    ).then((lvl) {
      _busy = false;
      if (lvl != null) _op((v) => MdOps.heading(v, level: lvl));
      if (mounted) _focus.requestFocus();
    });
  }

  String _now() {
    final d = DateTime.now();
    String t(int x) => x.toString().padLeft(2, '0');
    return '${t(d.day)}.${t(d.month)}.${d.year} ${t(d.hour)}:${t(d.minute)}';
  }

  Widget _btn(IconData icon, String tip, VoidCallback f, {String? label}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: f,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: label != null
              ? Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))
              : Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _toolbar() {
    return ExcludeFocus(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undo,
            builder: (_, v, __) => Row(children: [
              Opacity(opacity: v.canUndo ? 1 : 0.35, child: _btn(Icons.undo, 'Отменить', () => _undo.undo())),
              Opacity(opacity: v.canRedo ? 1 : 0.35, child: _btn(Icons.redo, 'Повторить', () => _undo.redo())),
            ]),
          ),
          _btn(Icons.title, 'Заголовок', _headingMenu),
          _btn(Icons.format_bold, 'Жирный', () => _op((v) => MdOps.wrap(v, '**', '**'))),
          _btn(Icons.format_italic, 'Курсив', () => _op((v) => MdOps.wrap(v, '*', '*'))),
          _btn(Icons.format_strikethrough, 'Зачёркнутый', () => _op((v) => MdOps.wrap(v, '~~', '~~'))),
          _btn(Icons.format_underlined, 'Подчёркнутый', () => _op((v) => MdOps.wrap(v, '++', '++'))),
          _btn(Icons.border_color_outlined, 'Выделение', () => _op((v) => MdOps.wrap(v, '==', '=='))),
          _btn(Icons.code, 'Код', () => _op(MdOps.code)),
          _btn(Icons.link, 'Ссылка', _link),
          _btn(Icons.format_list_bulleted, 'Маркированный список', () => _op((v) => MdOps.linePrefix(v, 'bullet'))),
          _btn(Icons.format_list_numbered, 'Нумерованный список', () => _op((v) => MdOps.linePrefix(v, 'number'))),
          _btn(Icons.check_box_outlined, 'Список с галочками', () => _op((v) => MdOps.linePrefix(v, 'check'))),
          _btn(Icons.format_quote, 'Цитата', () => _op((v) => MdOps.linePrefix(v, 'quote'))),
          _btn(Icons.horizontal_rule, 'Линия', () => _op(MdOps.hr)),
          _btn(Icons.table_chart_outlined, 'Таблица', () => _op(MdOps.table)),
          _btn(Icons.schedule, 'Дата и время', () => _op((v) => MdOps.insert(v, _now()))),
          _btn(Icons.image_outlined, 'Изображение', () => _attach(true)),
          _btn(Icons.attach_file, 'Файл', () => _attach(false)),
          _btn(Icons.visibility_outlined, 'Просмотр', () {
            _focus.unfocus();
            setState(() => _editing = false);
          }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Pal.dark(context);
    if (!_editing && b.content.trim().isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() => _editing = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focus.requestFocus();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: MdDoc(
            b.content,
            store: widget.store,
            onOpenNote: widget.onOpenNote,
            onChanged: (t) {
              c.text = t;
              b.content = t;
              widget.onChanged();
              setState(() {});
            },
          ),
        ),
      );
    }
    final mod = Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.iOS;
    SingleActivator key(LogicalKeyboardKey k) =>
        SingleActivator(k, control: !mod, meta: mod);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _toolbar(),
        ),
        CallbackShortcuts(
          bindings: {
            key(LogicalKeyboardKey.keyB): () => _op((v) => MdOps.wrap(v, '**', '**')),
            key(LogicalKeyboardKey.keyI): () => _op((v) => MdOps.wrap(v, '*', '*')),
            key(LogicalKeyboardKey.keyK): _link,
          },
          child: TextField(
            controller: c,
            focusNode: _focus,
            undoController: _undo,
            maxLines: null,
            minLines: 3,
            keyboardType: TextInputType.multiline,
            inputFormatters: [MdListFormatter()],
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Текст (Markdown: **жирный**, # заголовок, - список)',
            ),
            onChanged: (v) {
              b.content = v;
              widget.onChanged();
            },
          ),
        ),
      ],
    );
  }
}
