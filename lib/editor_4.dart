// ▸ Часть editor.dart: Редактор заметки (блоки, меню, экспорт, встраиваемый режим)  [содержит: _ExtEditorScreenState3]
part of 'editor.dart';

extension _ExtEditorScreenState3 on _EditorScreenState {

  /// Единое окно редактирования: блоки идут сплошным потоком, без рамок, заголовков и ручек.
  /// У вложений (не текст) справа — маленький крестик удаления.
  Widget _blockCard(int index, Block b) {
    if (b.type == 'text') {
      return Padding(key: ValueKey(b.id), padding: const EdgeInsets.symmetric(vertical: 2), child: _blockBody(b));
    }
    return Padding(
      key: ValueKey(b.id),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _blockBody(b)),
        IconButton(
          tooltip: 'Убрать ${_label(b.type).toLowerCase()}',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, size: 16, color: Pal.secondary(context)),
          onPressed: () => _removeBlock(b),
        ),
      ]),
    );
  }

  /// В конце заметки всегда есть пустой текстовый блок — можно продолжать печатать после таблицы и т.п.
  void _ensureTail() {
    if (n.blocks.isEmpty || n.blocks.last.type != 'text') n.blocks.add(Block(type: 'text'));
  }

  /// Просмотр: без рамок, ручек и кнопок добавления — только содержимое.
  Widget _viewBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _header(),
        for (final b in n.blocks)
          if (!(b.type == 'text' && b.content.trim().isEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: b.type == 'text'
                  ? MdTextBlock(
                      key: ValueKey('mdv${b.id}'),
                      store: s,
                      block: b,
                      controller: _ctlFor(b),
                      onChanged: _touch,
                      onOpenNote: _openNote,
                      viewOnly: true)
                  : b.type == 'quote'
                      ? Container(
                          padding: const EdgeInsets.only(left: 12),
                          decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: Pal.border(context), width: 3))),
                          child: Text(b.content, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16)))
                      : b.type == 'code'
                          ? Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Pal.card3(context), borderRadius: BorderRadius.circular(8)),
                              child: Text(b.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)))
                          : _blockBody(b),
            ),
        n.isGroup ? CommentsView(store: s, note: n) : const SizedBox(height: 16),
      ],
    );
  }

  Widget _addBtn(IconData icon, String label, VoidCallback f) {
    return TextButton.icon(
      icon: Icon(icon, size: 20),
      label: Text(label),
      onPressed: f,
    );
  }
}
