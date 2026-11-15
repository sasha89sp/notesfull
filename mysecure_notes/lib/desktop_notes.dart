import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ctx_menu.dart';
import 'editor.dart';
import 'models.dart';
import 'note_actions.dart';
import 'panes.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Десктопный вид заметок в три блока: папки и теги | список | редактор.
/// Блоки можно менять местами и растягивать; правая кнопка мыши — меню.
class DesktopNotes extends StatefulWidget {
  final Store store;
  final String initial;
  const DesktopNotes({super.key, required this.store, this.initial = 'all'});

  @override
  State<DesktopNotes> createState() => _DesktopNotesState();
}

class _DesktopNotesState extends State<DesktopNotes> {
  // выбор в первом блоке: all | fav | f:<id папки> | t:<тег>
  late String _sel = widget.initial;
  Note? _note;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _q = '';
  final Set<String> _open = {};

  Store get s => widget.store;
  NoteActions get _act => NoteActions(context, s);

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Note> _notes() {
    var l = s.notes.where((n) => !n.deleted && !n.isGroup).toList();
    if (_sel == 'fav') {
      l = l.where((n) => n.favorite).toList();
    } else if (_sel.startsWith('f:')) {
      final id = _sel.substring(2);
      l = l.where((n) => n.folder == id).toList();
    } else if (_sel.startsWith('t:')) {
      final t = _sel.substring(2);
      l = l.where((n) => n.tags.contains(t)).toList();
    }
    if (_q.isNotEmpty) {
      l = l.where((n) => s.matches(n, _q)).toList();
    }
    l.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return l;
  }

  void _newNote() {
    final n = Note.create(s.author, s.profileId, 'personal');
    if (_sel.startsWith('f:')) n.folder = _sel.substring(2);
    if (_sel.startsWith('t:')) n.tags.add(_sel.substring(2));
    s.notes.add(n);
    setState(() => _note = n);
  }

  Future<void> _newFolder([String parent = '']) async {
    final name = await _act.askName('Новая папка');
    if (name == null) return;
    s.addFolder(name, parent);
    if (parent.isNotEmpty) _open.add(parent);
    setState(() {});
  }

  void _save() {
    s.changed();
    if (mounted) toast(context, 'Сохранено');
  }

  void _scale(double d) {
    s.settings.fontScale = (s.settings.fontScale + d).clamp(0.7, 1.6);
    s.saveSettings();
    s.refresh();
  }

  // ------------------------------------------------------------ блок 1

  Widget _row(IconData icon, String label, String key,
      {int depth = 0, Widget? trailing, NoteFolder? folder}) {
    final sel = _sel == key;
    final cs = Theme.of(context).colorScheme;
    final row = Container(
      color: sel ? cs.primary.withOpacity(0.14) : null,
      padding: EdgeInsets.fromLTRB(8 + depth * 14.0, 4, 6, 4),
      child: Row(children: [
        Icon(icon, size: 15, color: sel ? cs.primary : null),
        const SizedBox(width: 6),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
        if (trailing != null) trailing,
      ]),
    );
    return CtxArea(
      onTap: () => setState(() => _sel = key),
      onMenu: (pos) async {
        if (folder == null) {
          if (key == 'all') {
            final a = await showCtx(context, pos, const [CtxItem('new', 'Новая папка', icon: Icons.create_new_folder_outlined)]);
            if (a == 'new') _newFolder();
          }
          return;
        }
        final a = await showCtx(context, pos, _act.folderItems(folder));
        if (a != null) {
          if (a == 'sub') _open.add(folder.id);
          await _act.runFolder(folder, a);
          if (a == 'del' && _sel == key) _sel = 'all';
          if (mounted) setState(() {});
        }
      },
      child: row,
    );
  }

  List<Widget> _tree(String parent, int depth) {
    final out = <Widget>[];
    for (final f in s.childFolders(parent)) {
      final kids = s.childFolders(f.id);
      final open = _open.contains(f.id);
      out.add(_row(
        open ? Icons.folder_open_outlined : Icons.folder_outlined,
        f.name,
        'f:${f.id}',
        depth: depth,
        folder: f,
        trailing: kids.isEmpty
            ? Text('${s.notesIn(f.id)}', style: TextStyle(fontSize: 11, color: Pal.secondary(context)))
            : InkWell(
                onTap: () => setState(() => open ? _open.remove(f.id) : _open.add(f.id)),
                child: Icon(open ? Icons.expand_less : Icons.expand_more, size: 16),
              ),
      ));
      if (open) out.addAll(_tree(f.id, depth + 1));
    }
    return out;
  }

  Widget _side() {
    final tags = <String>{};
    for (final n in s.notes.where((n) => !n.deleted && !n.isGroup)) {
      tags.addAll(n.tags);
    }
    final tl = tags.toList()..sort();
    return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
      _row(Icons.notes, 'Все заметки', 'all'),
      _row(Icons.star_border, 'Избранное', 'fav'),
      ..._tree('', 0),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
        child: TextButton.icon(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
          onPressed: _newFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 15),
          label: const Text('Новая папка'),
        ),
      ),
      if (tl.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 10, 10, 2),
          child: Text('Теги', style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
        ),
        for (final t in tl) _row(Icons.tag, t, 't:$t'),
      ],
    ]);
  }

  // ------------------------------------------------------------ блок 2

  Widget _list() {
    final list = _notes();
    final sec = Pal.secondary(context);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Поиск (Ctrl+F)', prefixIcon: Icon(Icons.search, size: 16)),
            ),
          ),
          IconButton(
              tooltip: 'Новая заметка (Ctrl+N)',
              visualDensity: VisualDensity.compact,
              onPressed: _newNote,
              icon: const Icon(Icons.note_add_outlined, size: 19)),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text('Заметок нет', style: TextStyle(color: sec, fontSize: 12.5)))
            : ListView.builder(
                itemCount: list.length,
                itemExtent: 62,
                itemBuilder: (_, i) {
                  final n = list[i];
                  final sel = _note?.id == n.id;
                  return CtxArea(
                    onTap: () => setState(() => _note = n),
                    onMenu: (pos) async {
                      final a = await showCtx(context, pos, _act.noteItems(n));
                      if (a == null) return;
                      final r = await _act.runNote(n, a);
                      if (!mounted) return;
                      setState(() {
                        if (r == 'open') _note = n;
                        if (r == 'deleted' && _note?.id == n.id) _note = null;
                      });
                    },
                    child: Container(
                      color: sel ? cs.primary.withOpacity(0.14) : null,
                      padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(n.title.isEmpty ? 'Без названия' : n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                          if (s.isPinned(n.id)) const Icon(Icons.push_pin, size: 12),
                          if (n.favorite) const Icon(Icons.star, size: 12, color: Color(0xFFFF9500)),
                        ]),
                        Text(n.preview(80),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: sec)),
                        Text(fmtDate(n.updatedAt), style: TextStyle(fontSize: 10.5, color: sec)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ------------------------------------------------------------ блок 3

  Widget _detail() {
    final n = _note;
    if (n == null || n.deleted) {
      return Center(
          child: Text('Выберите заметку или создайте новую (Ctrl+N)',
              style: TextStyle(color: Pal.secondary(context), fontSize: 13)));
    }
    return EditorScreen(
      key: ValueKey(n.id),
      store: s,
      note: n,
      embedded: true,
      onClosed: () => setState(() => _note = null),
    );
  }

  Map<ShortcutActivator, VoidCallback> get _keys {
    final m = <ShortcutActivator, VoidCallback>{};
    for (final (ctrl, meta) in [(true, false), (false, true)]) {
      m[SingleActivator(LogicalKeyboardKey.keyN, control: ctrl, meta: meta)] = _newNote;
      m[SingleActivator(LogicalKeyboardKey.keyF, control: ctrl, meta: meta)] = () => _searchFocus.requestFocus();
      m[SingleActivator(LogicalKeyboardKey.keyS, control: ctrl, meta: meta)] = _save;
      m[SingleActivator(LogicalKeyboardKey.equal, control: ctrl, meta: meta)] = () => _scale(0.1);
      m[SingleActivator(LogicalKeyboardKey.minus, control: ctrl, meta: meta)] = () => _scale(-0.1);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: s,
          builder: (context, _) => ThreePane(store: s, panes: {
            'side': PaneSpec('Блокноты', _side()),
            'list': PaneSpec('Заметки', _list()),
            'detail': PaneSpec('Редактор', _detail()),
          }),
        ),
      ),
    );
  }
}
