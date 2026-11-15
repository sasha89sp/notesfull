import 'package:flutter/material.dart';
import 'edit_cmd.dart';

/// Меню «Правка» верхней панели (как в Joplin). Пункты форматирования
/// действуют на последний активный Markdown-блок заметки.
class EditMenu {
  static Widget _i(String label, VoidCallback? f, [String? key]) => MenuItemButton(
        onPressed: f,
        trailingIcon:
            key == null ? null : Text(key, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
        child: Text(label),
      );

  static Widget build(BuildContext c, {required VoidCallback searchAll}) {
    const d = Divider(height: 1);
    return SubmenuButton(menuChildren: [
      _i('Копировать', EditCmd.copy, 'Ctrl+C'),
      _i('Вырезать', EditCmd.cut, 'Ctrl+X'),
      _i('Вставить', EditCmd.paste, 'Ctrl+V'),
      _i('Вставить как текст', EditCmd.paste, 'Ctrl+Shift+V'),
      _i('Вставить как Markdown', null), // конвертация HTML буфера пока не поддерживается
      _i('Выделить всё', EditCmd.selectAll, 'Ctrl+A'),
      d,
      _i('Отменить', EditCmd.undo, 'Ctrl+Z'),
      _i('Повторить', EditCmd.redo, 'Ctrl+Y'),
      d,
      _i('Жирный', EditCmd.bold, 'Ctrl+B'),
      _i('Курсив', EditCmd.italic, 'Ctrl+I'),
      _i('Ссылка', EditCmd.link, 'Ctrl+K'),
      _i('Код', EditCmd.code, 'Ctrl+`'),
      d,
      _i('Вставить время', EditCmd.insertTime),
      _i('Прикрепить файл', EditCmd.attachFile),
      _i('Вставить рисунок', null), // редактор рисунков не реализован
      d,
      _i('Удалить строку', EditCmd.deleteLine),
      _i('Дублировать строку', EditCmd.duplicateLine),
      _i('Комментировать/раскомментировать', EditCmd.toggleComment),
      _i('Сортировать выделенные строки', EditCmd.sortLines),
      _i('Уменьшить отступ', EditCmd.outdent),
      _i('Увеличить отступ', EditCmd.indent),
      _i('Переместить строку вниз', EditCmd.moveDown),
      _i('Переместить строку вверх', EditCmd.moveUp),
      d,
      _i('Искать во всех заметках', searchAll, 'F6'),
      _i('Искать в текущей заметке', () => EditCmd.findInNote(c), 'Ctrl+F'),
    ], child: const Text('Правка'));
  }
}
