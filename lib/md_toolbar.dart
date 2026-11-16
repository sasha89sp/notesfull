// ▸ Общая панель форматирования Markdown для единого окна редактирования заметки (действует на активный блок)
import 'package:flutter/material.dart';
import 'edit_cmd.dart';
import 'md_ops.dart';
import 'widgets.dart';

/// Одна панель на всю заметку: применяется к тому текстовому блоку, где стоит курсор.
class MdToolbar extends StatelessWidget {
  const MdToolbar({super.key});

  Widget _b(IconData i, String tip, VoidCallback f) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: f,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(i, size: 20)),
        ),
      );

  void _heading(BuildContext c) {
    showModalBottomSheet<int>(
      context: c,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 6; i++)
            ListTile(
              dense: true,
              title: Text('Заголовок $i', style: TextStyle(fontSize: 26 - i * 2.0, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, i),
            ),
          ListTile(dense: true, title: const Text('Обычный текст'), onTap: () => Navigator.pop(ctx, 0)),
        ]),
      ),
    ).then((l) {
      if (l != null) EditCmd.op((v) => MdOps.heading(v, level: l));
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Pal.dark(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExcludeFocus(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _b(Icons.undo, 'Отменить', EditCmd.undo),
            _b(Icons.redo, 'Повторить', EditCmd.redo),
            _b(Icons.title, 'Заголовок', () => _heading(context)),
            _b(Icons.format_bold, 'Жирный', EditCmd.bold),
            _b(Icons.format_italic, 'Курсив', EditCmd.italic),
            _b(Icons.format_strikethrough, 'Зачёркнутый', () => EditCmd.op((v) => MdOps.wrap(v, '~~', '~~'))),
            _b(Icons.format_underlined, 'Подчёркнутый', () => EditCmd.op((v) => MdOps.wrap(v, '++', '++'))),
            _b(Icons.border_color_outlined, 'Выделение', () => EditCmd.op((v) => MdOps.wrap(v, '==', '=='))),
            _b(Icons.code, 'Код', EditCmd.code),
            _b(Icons.link, 'Ссылка', EditCmd.link),
            _b(Icons.format_list_bulleted, 'Маркированный список', () => EditCmd.op((v) => MdOps.linePrefix(v, 'bullet'))),
            _b(Icons.format_list_numbered, 'Нумерованный список', () => EditCmd.op((v) => MdOps.linePrefix(v, 'number'))),
            _b(Icons.check_box_outlined, 'Список с галочками', () => EditCmd.op((v) => MdOps.linePrefix(v, 'check'))),
            _b(Icons.format_quote, 'Цитата', () => EditCmd.op((v) => MdOps.linePrefix(v, 'quote'))),
            _b(Icons.horizontal_rule, 'Линия', () => EditCmd.op(MdOps.hr)),
            _b(Icons.table_chart_outlined, 'Таблица (Markdown)', () => EditCmd.op(MdOps.table)),
            _b(Icons.schedule, 'Дата и время', EditCmd.insertTime),
            _b(Icons.image_outlined, 'Изображение', () => EditCmd.md?.attach(true)),
            _b(Icons.attach_file, 'Файл', EditCmd.attachFile),
          ]),
        ),
      ),
    );
  }
}
