part of 'editor.dart';

extension _ExtEditorScreenState3 on _EditorScreenState {

  Widget _blockCard(int index, Block b) {
    return Container(
      key: ValueKey(b.id),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        color: Pal.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.border(context), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_handle,
                    size: 20, color: Pal.secondary(context)),
              ),
              const SizedBox(width: 8),
              Text(_label(b.type),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Pal.secondary(context))),
              const Spacer(),
              IconButton(
                tooltip: 'Удалить блок',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _removeBlock(b),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _blockBody(b),
          ),
        ],
      ),
    );
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
