// ▸ Часть notes_page.dart: Список заметок (мобильный вид), главная  [содержит: _ExtNotesListState1]
part of 'notes_page.dart';

extension _ExtNotesListState1 on _NotesListState {

  Store get s => widget.store;

  bool get _isVault => widget.filter.startsWith('vault:');

  String _group(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (diff < 7) return 'На этой неделе';
    return 'Ранее';
  }

  void _open(Note n) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EditorScreen(store: s, note: n),
    ));
  }

  void create() {
    final n = Note.create(
        s.author, s.profileId, _isVault ? widget.filter.substring(6) : 'personal');
    if (!widget.home && !_isVault) n.folder = _cur;
    s.notes.add(n);
    _open(n);
  }

  Future<void> _confirmDelete(Note n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить заметку?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      n.deleted = true;
      n.updatedAt = nowMs();
      s.changed();
    }
  }

  // ------------------------------------------------------------ папки

  Future<String?> _askName(String title, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Готово')),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  List<MapEntry<NoteFolder, int>> _flat(String parent, int depth, String? exclude) {
    final out = <MapEntry<NoteFolder, int>>[];
    for (final f in s.childFolders(parent)) {
      if (f.id == exclude) continue;
      out.add(MapEntry(f, depth));
      out.addAll(_flat(f.id, depth + 1, exclude));
    }
    return out;
  }

  /// Выбор папки. Возвращает id, '' — корень, null — отмена.
  Future<String?> _pickFolder({String? exclude}) {
    final flat = _flat('', 0, exclude);
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Переместить в папку'),
        children: [
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Без папки (корень)'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final e in flat)
            Padding(
              padding: EdgeInsets.only(left: 16.0 * e.value),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(e.key.name),
                onTap: () => Navigator.pop(ctx, e.key.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _newFolder() async {
    final n = await _askName('Новая папка');
    if (n != null) s.addFolder(n, _cur);
  }

  Future<void> _folderMenu(NoteFolder f) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(ctx, 'ren')),
          ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Переместить'),
              onTap: () => Navigator.pop(ctx, 'mv')),
          ListTile(
              leading: Icon(s.isFolderFav(f.id) ? Icons.star : Icons.star_border),
              title: Text(s.isFolderFav(f.id) ? 'Убрать из избранного' : 'В избранное'),
              onTap: () => Navigator.pop(ctx, 'fav')),
          ListTile(
              leading: Icon(s.isPinned(f.id) ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(s.isPinned(f.id) ? 'Открепить с главной' : 'Закрепить на главной'),
              onTap: () => Navigator.pop(ctx, 'pin')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить папку (содержимое сохранится)'),
              onTap: () => Navigator.pop(ctx, 'del')),
        ]),
      ),
    );
    if (act == 'ren') {
      final n = await _askName('Переименовать папку', f.name);
      if (n != null) s.renameFolder(f, n);
    } else if (act == 'mv') {
      final to = await _pickFolder(exclude: f.id);
      if (to != null) s.moveFolder(f, to);
    } else if (act == 'fav') {
      s.toggleFolderFav(f.id);
    } else if (act == 'pin') {
      s.togglePin(f.id);
    } else if (act == 'del') {
      s.deleteFolder(f);
    }
  }

  Future<void> _noteMenu(Note n) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: Icon(n.favorite ? Icons.star : Icons.star_border),
              title: Text(n.favorite ? 'Убрать из избранного' : 'В избранное'),
              onTap: () => Navigator.pop(ctx, 'fav')),
          ListTile(
              leading: Icon(s.isPinned(n.id) ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(s.isPinned(n.id) ? 'Открепить с главной' : 'Закрепить на главной'),
              onTap: () => Navigator.pop(ctx, 'pin')),
          if (!n.isGroup)
            ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Переместить в папку'),
                onTap: () => Navigator.pop(ctx, 'mv')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () => Navigator.pop(ctx, 'del')),
        ]),
      ),
    );
    if (act == 'mv') {
      final to = await _pickFolder();
      if (to != null) s.moveNote(n, to);
    } else if (act == 'fav') {
      n.favorite = !n.favorite;
      n.updatedAt = nowMs();
      s.changed();
    } else if (act == 'pin') {
      s.togglePin(n.id);
    } else if (act == 'del') {
      await _confirmDelete(n);
    }
  }

  /// Закреплённые на главной заметки и папки.
  Widget _pinnedBlock() {
    final cards = <Widget>[];
    for (final id in List<String>.of(s.settings.pinned)) {
      final f = s.folderById(id);
      if (f != null) {
        cards.add(AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => widget.onOpenFolder?.call(f.id),
          onLongPress: () => _folderMenu(f),
          child: Row(children: [
            Icon(Icons.folder_outlined, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            Icon(Icons.push_pin, size: 16, color: Pal.secondary(context)),
          ]),
        ));
        continue;
      }
      Note? n;
      for (final x in s.notes) {
        if (x.id == id && !x.deleted) n = x;
      }
      if (n != null) cards.add(_card(n));
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text('Закреплённое',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: Pal.secondary(context))),
      ),
      ...cards,
    ]);
  }
}
