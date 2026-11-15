part of 'editor.dart';

extension _ExtEditorScreenState2 on _EditorScreenState { // режим просмотра (true) или правки (false)

  /// Все метаданные заметки — в одной маленькой кнопке: хранилище, теги, автор и даты.
  void _showMeta() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('О заметке', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(n.isGroup ? Icons.group_outlined : Icons.lock_outline, size: 18, color: Pal.secondary(context)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _vaults().any((v) => v.key == n.vault) ? n.vault : 'personal',
                  underline: const SizedBox.shrink(),
                  items: [for (final v in _vaults()) DropdownMenuItem(value: v.key, child: Text(v.value))],
                  onChanged: _ro
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => n.vault = v);
                          setSheet(() {});
                          _touch();
                        },
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(children: [
                for (final t in n.tags)
                  TagChip(t, onDelete: () {
                    setState(() => n.tags.remove(t));
                    setSheet(() {});
                    _touch();
                  }),
                ActionChip(
                  label: const Text('+ тег'),
                  onPressed: () async {
                    await _addTag();
                    setSheet(() {});
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Создал: ${n.author.isEmpty ? '—' : n.author} · ${fmtDate(n.createdAt)}\n'
                'Изменено: ${n.editor.isEmpty ? '—' : n.editor} · ${fmtDate(n.updatedAt)}',
                style: TextStyle(color: Pal.secondary(context), fontSize: 12),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_view)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(n.title.isEmpty ? 'Без названия' : n.title,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            )
          else
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Название',
              border: InputBorder.none,
            ),
            onChanged: (v) {
              n.title = v;
              _touch();
            },
          ),
          const SizedBox(height: 4),
          if (_ro)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Pal.card(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Создатель общей папки ограничил вам редактирование: изменения не сохраняются.'),
            ),
        ],
      ),
    );
  }

  String _label(String t) {
    switch (t) {
      case 'checklist':
        return 'Чек-лист';
      case 'quote':
        return 'Цитата';
      case 'code':
        return 'Код';
      case 'table':
        return 'Таблица';
      case 'voice':
        return 'Голосовая запись';
      case 'ics':
        return 'Календарь (.ics)';
      case 'image':
        return 'Фото';
      case 'file':
        return 'Файл';
      default:
        return 'Текст';
    }
  }

  Widget _blockBody(Block b) {
    switch (b.type) {
      case 'checklist':
        return _checklist(b);
      case 'table':
        return _tableBlock(b);
      case 'voice':
        return VoiceBlockView(
            key: ValueKey('v${b.id}'),
            store: s,
            block: b,
            onChanged: _touch);
      case 'ics':
        return IcsBlockView(key: ValueKey('ics${b.id}'), store: s, block: b, onChanged: _touch);
      case 'image':
        return ImageBlockView(key: ValueKey('i${b.id}'), store: s, block: b);
      case 'file':
        return FileBlockView(store: s, block: b);
    }

    if (b.type == 'text') {
      return MdTextBlock(
        key: ValueKey('md${b.id}'),
        store: s,
        block: b,
        controller: _ctlFor(b),
        onChanged: _touch,
        onOpenNote: _openNote,
      );
    }

    return TextField(
      controller: _ctlFor(b),
      maxLines: null,
      minLines: b.type == 'code' ? 3 : 2,
      keyboardType: TextInputType.multiline,
      style: b.type == 'code'
          ? const TextStyle(fontFamily: 'monospace', fontSize: 14)
          : b.type == 'quote'
              ? const TextStyle(fontStyle: FontStyle.italic, fontSize: 17)
              : const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: b.type == 'text' ? 'Текст (поддерживается Markdown)' : null,
      ),
      onChanged: (v) {
        b.content = v;
        _touch();
      },
    );
  }

  Widget _tableBlock(Block b) {
    final t = b.table;
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TableScreen(
              block: b, title: n.title, onChanged: _touch),
        ));
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          const Icon(Icons.table_chart_outlined),
          const SizedBox(width: 10),
          Text('Таблица ${t.rows}×${t.cols} — открыть'),
        ]),
      ),
    );
  }

  Widget _checklist(Block b) {
    return Column(
      children: [
        for (final item in b.items)
          Row(
            key: ObjectKey(item),
            children: [
              Checkbox(
                value: item.done,
                onChanged: (v) {
                  setState(() => item.done = v ?? false);
                  _touch();
                },
              ),
              Expanded(
                child: TextField(
                  controller: _ictlFor(item),
                  decoration: const InputDecoration(
                      border: InputBorder.none, hintText: 'Пункт'),
                  style: TextStyle(
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    color: item.done ? Pal.muted(context) : null,
                  ),
                  onChanged: (v) {
                    item.text = v;
                    _touch();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    b.items.remove(item);
                    _ictl.remove(item)?.dispose();
                  });
                  _touch();
                },
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить пункт'),
            onPressed: () {
              setState(() => b.items.add(CheckItem('')));
              _touch();
            },
          ),
        ),
      ],
    );
  }
}
