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
  final String filter; // all | personal | family | fav
  final String? tag;
  final bool home;
  final VoidCallback onClearTag;
  const NotesList({
    super.key,
    required this.store,
    required this.filter,
    required this.tag,
    required this.home,
    required this.onClearTag,
  });

  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  String _q = '';
  String _seg = 'all'; // all | notes | tables
  final _search = TextEditingController();

  Store get s => widget.store;

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
    final f = widget.filter;
    final n = Note.create(s.author, s.profileId, f == 'family' ? 'family' : 'personal');
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

  Widget _card(Note n) {
    final prev = n.preview(120);
    return AppCard(
      onTap: () => _open(n),
      onLongPress: () => _confirmDelete(n),
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
              n.vault == 'family' ? Icons.group_outlined : Icons.lock_outline,
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
              n.vault == 'family' && n.editor.isNotEmpty
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
        var list = s.notes.where((n) => !n.deleted).toList();
        switch (widget.filter) {
          case 'personal':
            list = list.where((n) => n.vault == 'personal').toList();
            break;
          case 'family':
            list = list.where((n) => n.vault == 'family').toList();
            break;
          case 'fav':
            list = list.where((n) => n.favorite).toList();
            break;
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
          list = list
              .where((n) =>
                  n.title.toLowerCase().contains(q) ||
                  n.tags.any((t) => t.toLowerCase().contains(q)) ||
                  n.preview(100000).toLowerCase().contains(q))
              .toList();
        }
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final items = <Widget>[];
        if (widget.home) items.add(_upcoming());
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
              child: Text('Заметок пока нет',
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
