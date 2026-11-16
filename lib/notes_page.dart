// ▸ Список заметок (мобильный вид), главная
import 'package:flutter/material.dart';
import 'editor.dart';
import 'event_screen.dart';
import 'calendars.dart';
import 'edit_cmd.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

part 'notes_page_2.dart';
part 'notes_page_3.dart';


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
  String _cur = ''; // текущая папка заметок
  final _search = TextEditingController();

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
                focusNode: EditCmd.searchFocus,
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
  }}