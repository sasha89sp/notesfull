import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'editor.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Десктопный вид заметок в три колонки, как в Joplin:
/// папки и теги | список заметок | редактор.
class DesktopNotes extends StatefulWidget {
  final Store store;
  final String initial;
  const DesktopNotes({super.key, required this.store, this.initial = 'all'});

  @override
  State<DesktopNotes> createState() => _DesktopNotesState();
}

class _DesktopNotesState extends State<DesktopNotes> {
  // выбор в первой колонке: all | fav | f:<id папки> | t:<тег>
  late String _sel = widget.initial;
  Note? _note;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _q = '';
  final Set<String> _open = {};

  Store get s => widget.store;

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
      final q = _q.toLowerCase();
      l = l.where((n) => s.matches(n, q)).toList();
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

  Future<void> _newFolder() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    final name = c.text.trim();
    c.dispose();
    if (ok != true || name.isEmpty) return;
    final parent = _sel.startsWith('f:') ? _sel.substring(2) : '';
    s.addFolder(name, parent);
    if (parent.isNotEmpty) _open.add(parent);
    setState(() {});
  }

  // ------------------------------------------------------------ колонка 1

  Widget _row(IconData icon, String label, String key, {int depth = 0, Widget? trailing}) {
    final sel = _sel == key;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _sel = key),
      child: Container(
        color: sel ? cs.primary.withOpacity(0.14) : null,
        padding: EdgeInsets.fromLTRB(12 + depth * 16.0, 7, 8, 7),
        child: Row(children: [
          Icon(icon, size: 18, color: sel ? cs.primary : null),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (trailing != null) trailing,
        ]),
      ),
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
        trailing: kids.isEmpty
            ? null
            : InkWell(
                onTap: () => setState(() => open ? _open.remove(f.id) : _open.add(f.id)),
                child: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
              ),
      ));
      if (open) out.addAll(_tree(f.id, depth + 1));
    }
    return out;
  }

  Widget _col1() {
    final tags = <String>{};
    for (final n in s.notes.where((n) => !n.deleted && !n.isGroup)) {
      tags.addAll(n.tags);
    }
    final tl = tags.toList()..sort();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Row(children: [
          const Expanded(child: Text('Блокноты', style: TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
              tooltip: 'Новая папка', onPressed: _newFolder, icon: const Icon(Icons.create_new_folder_outlined)),
        ]),
      ),
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          _row(Icons.notes, 'Все заметки', 'all'),
          _row(Icons.star_border, 'Избранное', 'fav'),
          ..._tree('', 0),
          if (tl.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Text('Теги', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
            ),
            for (final t in tl) _row(Icons.tag, t, 't:$t'),
          ],
        ]),
      ),
    ]);
  }

  // ------------------------------------------------------------ колонка 2

  Widget _col2() {
    final list = _notes();
    final sec = Pal.secondary(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Поиск', prefixIcon: Icon(Icons.search, size: 18)),
            ),
          ),
          IconButton(tooltip: 'Новая заметка', onPressed: _newNote, icon: const Icon(Icons.note_add_outlined)),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text('Заметок нет', style: TextStyle(color: sec)))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final n = list[i];
                  final sel = _note?.id == n.id;
                  return InkWell(
                    onTap: () => setState(() => _note = n),
                    child: Container(
                      color: sel ? Theme.of(context).colorScheme.primary.withOpacity(0.14) : null,
                      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(n.title.isEmpty ? 'Без названия' : n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (s.isPinned(n.id)) const Icon(Icons.push_pin, size: 14),
                          if (n.favorite) const Icon(Icons.star, size: 14),
                        ]),
                        Text(n.preview(90),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: sec)),
                        Text(fmtDate(n.updatedAt), style: TextStyle(fontSize: 11, color: sec)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ------------------------------------------------------------ колонка 3

  Widget _col3() {
    final n = _note;
    if (n == null || n.deleted) {
      return Center(
          child: Text('Выберите заметку или создайте новую',
              style: TextStyle(color: Pal.secondary(context))));
    }
    return EditorScreen(
      key: ValueKey(n.id),
      store: s,
      note: n,
      embedded: true,
      onClosed: () => setState(() => _note = null),
    );
  }

  void _save() {
    s.changed();
    if (mounted) toast(context, 'Сохранено');
  }

  void _scale(double d) {
    s.settings.fontScale = (s.settings.fontScale + d).clamp(0.8, 1.6);
    s.saveSettings();
    s.refresh();
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
      child: Focus(autofocus: true, child: _cols()),
    );
  }

  Widget _cols() {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final line = BorderSide(color: Pal.border(context), width: 0.5);
        return Row(children: [
          Container(
              width: 240,
              decoration: BoxDecoration(border: Border(right: line)),
              child: _col1()),
          Container(
              width: 330,
              decoration: BoxDecoration(border: Border(right: line)),
              child: _col2()),
          Expanded(child: _col3()),
        ]);
      },
    );
  }
}
