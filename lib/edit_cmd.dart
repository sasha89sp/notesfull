import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'md_lines.dart';
import 'md_ops.dart';

/// Активный Markdown-блок: меню «Правка» применяет к нему форматирование.
class ActiveMd {
  final void Function(TextEditingValue Function(TextEditingValue)) op;
  final Future<void> Function() link;
  final Future<void> Function(bool image) attach;
  final VoidCallback undo, redo;
  final bool Function(String) find;
  final String Function() now;
  ActiveMd(this.op, this.link, this.attach, this.undo, this.redo, this.find, this.now);
}

/// Команды меню «Правка». Запоминает последнее поле ввода (меню забирает фокус
/// при нажатии, поэтому «текущее» поле берётся из слушателя фокуса).
class EditCmd {
  static ActiveMd? md;
  static EditableTextState? _last;
  static final FocusNode searchFocus = FocusNode(debugLabel: 'notesSearch');
  static bool _inited = false;

  static void init() {
    if (_inited) return;
    _inited = true;
    FocusManager.instance.addListener(() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      final st = ctx?.findAncestorStateOfType<EditableTextState>();
      if (st != null) _last = st;
    });
  }

  static EditableTextState? get _st {
    final st = _last;
    return st != null && st.mounted ? st : null;
  }

  static bool get hasField => _st != null;
  static bool get hasMd => md != null && _st != null;

  static void copy() => _st?.copySelection(SelectionChangedCause.toolbar);
  static void cut() => _st?.cutSelection(SelectionChangedCause.toolbar);
  static void paste() => _st?.pasteText(SelectionChangedCause.toolbar);
  static void selectAll() => _st?.selectAll(SelectionChangedCause.toolbar);

  static void undo() {
    if (md != null) {
      md!.undo();
    } else {
      final c = _st?.context;
      if (c != null) Actions.maybeInvoke(c, const UndoTextIntent(SelectionChangedCause.toolbar));
    }
  }

  static void redo() {
    if (md != null) {
      md!.redo();
    } else {
      final c = _st?.context;
      if (c != null) Actions.maybeInvoke(c, const RedoTextIntent(SelectionChangedCause.toolbar));
    }
  }

  static void op(TextEditingValue Function(TextEditingValue) f) => md?.op(f);
  static void bold() => op((v) => MdOps.wrap(v, '**', '**'));
  static void italic() => op((v) => MdOps.wrap(v, '*', '*'));
  static void code() => op(MdOps.code);
  static void link() => md?.link();
  static void insertTime() => op((v) => MdOps.insert(v, md!.now()));
  static void attachFile() => md?.attach(false);
  static void deleteLine() => op(MdLines.deleteLine);
  static void duplicateLine() => op(MdLines.duplicateLine);
  static void toggleComment() => op(MdLines.toggleComment);
  static void sortLines() => op(MdLines.sortLines);
  static void indent() => op(MdLines.indent);
  static void outdent() => op(MdLines.outdent);
  static void moveUp() => op((v) => MdLines.move(v, up: true));
  static void moveDown() => op((v) => MdLines.move(v, up: false));

  /// Поиск в текущей заметке: следующее вхождение после выделения.
  static Future<void> findInNote(BuildContext c) async {
    final m = md;
    if (m == null) return;
    final ctl = TextEditingController();
    final q = await showDialog<String>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Поиск в заметке'),
        content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Найти'),
            onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Найти')),
        ],
      ),
    );
    ctl.dispose();
    if (q == null || q.isEmpty) return;
    if (!m.find(q) && c.mounted) {
      ScaffoldMessenger.maybeOf(c)?.showSnackBar(const SnackBar(content: Text('Не найдено')));
    }
  }
}
