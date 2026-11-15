part of 'notes_page.dart';

extension _ExtNotesListState2 on _NotesListState {

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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                style: TextStyle(color: Pal.secondary(context), fontSize: 14, height: 1.4)),
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
              style: TextStyle(color: Pal.muted(context), fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _upcoming() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = s.events
        .where((e) => !e.deleted && !e.done && e.end >= now && Cals.visible(s.settings, e))
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
}
