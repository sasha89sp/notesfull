import 'package:flutter/material.dart';
import 'editor.dart';
import 'event_screen.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Список заметок. home=true — главная (ближайшие события сверху),
/// иначе вкладка «Заметки» с сегментами [Все] [Заметки] [Таблицы].
class NotesList extends StatefulWidget {
  final Store store;
  final String filter; // all (личные) | fav | vault:<vault> (заметки общей папки)
  final String? tag;
  final bool home;
  final String folder; // папка, которую нужно открыть (из меню слева)
  final VoidCallback onClearTag;
  final void Function(String folderId)? onOpenFolder;
  const NotesList({
    super.key,
    required this.store,
    required this.filter,
    required this.tag,
    required this.home,
    required this.onClearTag,
    this.folder = '',
    this.onOpenFolder,
  });

  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  String _q = '';
  String _seg = 'all'; // all | notes | tables
  String _cur = ''; // текущая папка заметок
  final _search = TextEditingController();

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    _cur = widget.folder;
  }

  @override
  void didUpdateWidget(NotesList old) {
    super.didUpdateWidget(old);
    if (old.folder != widget.folder) _cur = widget.folder;
  }

  bool get _isVault => widget.filter.startsWith('vault:');

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

  Widget _folderBar() {
    final subs = s.childFolders(_cur);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (_cur.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Выше',
            onPressed: () =>
                setState(() => _cur = s.folderById(_cur)?.parent ?? ''),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: _cur.isEmpty ? 4 : 0),
            child: Text(_cur.isEmpty ? 'Папки' : s.folderPath(_cur),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Pal.secondary(context))),
          ),
        ),
        IconButton(
          tooltip: 'Новая папка',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: _newFolder,
        ),
      ]),
      for (final f in subs)
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => setState(() => _cur = f.id),
          onLongPress: () => _folderMenu(f),
          child: Row(children: [
            Icon(Icons.folder_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Text(f.name,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${s.notesIn(f.id)}',
                style: TextStyle(color: Pal.secondary(context))),
            Icon(Icons.chevron_right, color: Pal.secondary(context)),
          ]),
        ),
    ]);
  }

  Widget _card(Note n) {
    final prev = n.preview(120);
    return AppCard(
      onTap: () => _open(n),
      onLongPress: () => _noteMenu(n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                n.title.isEmpty ? 'Без названия' : n.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            if (n.favorite)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.star, size: 16, color: Color(0xFFFF9500)),
              ),
            Icon(
              n.isGroup ? Icons.group_outlined : Icons.lock_outline,
              size: 16,
              color: Pal.secondary(context),
            ),
          ]),
          if (prev.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(prev,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Pal.secondary(context), fontSize: 15)),
          ],
          if (n.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(children: [for (final t in n.tags) TagChip(t)]),
          ],
          const SizedBox(height: 4),
          Text(
              n.isGroup && n.editor.isNotEmpty
                  ? '${n.editor} · ${fmtDate(n.updatedAt)}'
                  : fmtDate(n.updatedAt),
              style: TextStyle(color: Pal.secondary(context), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _upcoming() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = s.events
        .where((e) => !e.deleted && !e.done && e.end >= now)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
        child: Text('Ближайшее',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Pal.secondary(context))),
      ),
      for (final e in list.take(2))
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  EventScreen(store: s, event: e, isNew: false))),
          child: Row(children: [
            Icon(e.isTask ? Icons.check_circle_outline : Icons.event,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title.isEmpty ? 'Без названия' : e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        e.allDay
                            ? fmtDay(e.startDt)
                            : '${fmtDay(e.startDt)}, ${fmtTime(e.startDt)}',
                        style: TextStyle(
                            color: Pal.secondary(context), fontSize: 13)),
                  ]),
            ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (_cur.isNotEmpty && s.folderById(_cur) == null) _cur = '';
        final foldersMode =
            !widget.home && _q.isEmpty && widget.tag == null && !_isVault && widget.filter != 'fav';
        var list = s.notes.where((n) => !n.deleted).toList();
        if (foldersMode) {
          list = list.where((n) {
            final f = n.folder.isNotEmpty && s.folderById(n.folder) != null
                ? n.folder
                : '';
            return f == _cur;
          }).toList();
        }
        if (_isVault) {
          final v = widget.filter.substring(6);
          list = list.where((n) => n.vault == v).toList();
        } else if (widget.filter == 'fav') {
          list = list.where((n) => n.favorite).toList();
        } else {
          list = list.where((n) => n.vault == 'personal').toList(); // общие — в разделе «Общая папка»
        }
        if (widget.tag != null) {
          list = list.where((n) => n.tags.contains(widget.tag)).toList();
        }
        if (!widget.home) {
          if (_seg == 'notes') {
            list = list.where((n) => !n.hasTable).toList();
          } else if (_seg == 'tables') {
            list = list.where((n) => n.hasTable).toList();
          }
        }
        if (_q.isNotEmpty) {
          final q = _q.toLowerCase();
          list = list.where((n) => s.matches(n, q)).toList();
        }
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final items = <Widget>[];
        if (widget.home) items.add(_upcoming());
        if (widget.home) items.add(_pinnedBlock());
        if (foldersMode) items.add(_folderBar());
        String? lastG;
        for (final n in list) {
          final g = _group(n.updatedAt);
          if (g != lastG) {
            items.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
              child: Text(g,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Pal.secondary(context))),
            ));
            lastG = g;
          }
          items.add(_card(n));
        }
        if (list.isEmpty) {
          items.add(Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text(foldersMode && _cur.isNotEmpty ? 'В этой папке пусто' : 'Заметок пока нет',
                  style: TextStyle(color: Pal.secondary(context), fontSize: 17)),
            ),
          ));
        }

        return Stack(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _q = '');
                          }),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            if (!widget.home)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('Все')),
                      ButtonSegment(value: 'notes', label: Text('Заметки')),
                      ButtonSegment(value: 'tables', label: Text('Таблицы')),
                    ],
                    selected: {_seg},
                    onSelectionChanged: (v) => setState(() => _seg = v.first),
                  ),
                ),
              ),
            if (widget.tag != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TagChip(widget.tag!, onDelete: widget.onClearTag),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                children: items,
              ),
            ),
          ]),
          if (!widget.home) Fab(onPressed: create),
        ]);
      },
    );
  }
}
