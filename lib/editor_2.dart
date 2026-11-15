part of 'editor.dart';

extension _ExtEditorScreenState1 on _EditorScreenState {

  Note get n => widget.note;
  Store get s => widget.store;

  String _sig() => jsonEncode({
        't': n.title,
        'b': n.blocks.map((b) => b.toJson()).toList(),
      });

  /// Куда можно положить заметку: только себе или в одну из общих папок.
  List<MapEntry<String, String>> _vaults() => [
        const MapEntry('personal', 'Только я'),
        for (final g in s.settings.groups.where((g) => !g.removed))
          MapEntry(g.vault, g.name.isEmpty ? 'Общая папка' : g.name),
      ];

  Group? get _grp => n.isGroup ? Groups.byVault(s.settings, n.vault) : null;

  bool get _ro {
    final g = _grp;
    return g != null && !g.canEditNote(n, s.settings.profileId);
  }

  void _touch() {
    if (_ro) return;
    n.updatedAt = nowMs();
    final gn = _grp?.myName ?? '';
    n.editor = gn.isEmpty ? s.author : gn;
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 600), () {
      s.changed();
      Hub.noteRenamed(s, n);
    });
  }

  TextEditingController _ctlFor(Block b) =>
      _ctl.putIfAbsent(b.id, () => TextEditingController(text: b.content));

  TextEditingController _ictlFor(CheckItem i) =>
      _ictl.putIfAbsent(i, () => TextEditingController(text: i.text));

  void _addBlock(String type) {
    setState(() {
      final b = Block(
        type: type,
        items: type == 'checklist' ? [CheckItem('')] : null,
      );
      if (type == 'table') b.table = TableData.empty(4, 4);
      n.blocks.add(b);
    });
    _touch();
  }

  Future<void> _addImage() async {
    final b = await pickImageBlock(context, s);
    if (b == null) return;
    setState(() => n.blocks.add(b));
    _touch();
  }

  Future<void> _addFile() async {
    final b = await pickFileBlock(context, s);
    if (b == null) return;
    setState(() => n.blocks.add(b));
    _touch();
  }

  void _removeBlock(Block b) {
    setState(() {
      n.blocks.remove(b);
      _ctl.remove(b.id)?.dispose();
      for (final i in b.items) {
        _ictl.remove(i)?.dispose();
      }
    });
    _touch();
  }

  Future<void> _exportMd() async {
    final safe = (n.title.trim().isEmpty ? 'note' : n.title.trim()).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final hasFiles = n.attachmentIds().any(s.hasAttachment);
      final ok = hasFiles
          ? await saveBytes('$safe.zip', await JexIo.exportMarkdown(s, [n]))
          : await saveBytes('$safe.md',
              utf8.encode('# ${n.title}\n\n${Jex.bodyOf(n, (b) => null)}\n'));
      if (ok && mounted) toast(context, 'Экспортировано');
    } catch (e) {
      if (mounted) toast(context, 'Ошибка экспорта: $e');
    }
  }

  Future<void> _exportPdf() async {
    final safe = (n.title.trim().isEmpty ? 'note' : n.title.trim()).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final ok = await saveBytes('$safe.pdf', await PdfExport.build(s, [n]));
      if (ok && mounted) toast(context, 'PDF сохранён');
    } catch (e) {
      if (mounted) toast(context, 'Ошибка PDF: $e');
    }
  }

  void _menu(String v) {
    if (v == 'pdf') {
      _exportPdf();
      return;
    }
    if (v == 'event') {
      _toCalendar();
    } else if (v == 'delete') {
      n.deleted = true;
      n.updatedAt = nowMs();
      Hub.noteDeleted(s, n);
      if (widget.embedded) {
        widget.onClosed?.call();
      } else {
        Navigator.of(context).pop();
      }
    } else if (v == 'history') {
      _showHistory();
    } else if (v == 'md') {
      _exportMd();
    } else if (v == 'fav') {
      setState(() => n.favorite = !n.favorite);
      _touch();
    }
  }

  /// Заметка → календарь: событие создаётся автоматически, даже если модуль
  /// «Календарь» отключён.
  Future<void> _toCalendar() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 10));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: (now.hour + 1) % 24, minute: 0));
    if (t == null || !mounted) return;
    final when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    Hub.eventFromNote(s, n, when);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Событие добавлено в календарь')));
    }
  }

  /// Ссылка вида [текст](:/id) на другую заметку.
  void _openNote(String id) {
    for (final x in s.notes) {
      if (x.id == id && !x.deleted) {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EditorScreen(store: s, note: x)));
        return;
      }
    }
    toast(context, 'Заметка не найдена');
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        if (n.history.isEmpty) {
          return const SizedBox(
            height: 140,
            child: Center(child: Text('Версий пока нет')),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            for (final v in n.history)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(fmtDate(v.at)),
                subtitle: Text(v.title.isEmpty ? 'Без названия' : v.title),
                trailing: const Text('Откатить'),
                onTap: () {
                  _restore(v);
                  Navigator.pop(ctx);
                },
              ),
          ],
        );
      },
    );
  }

  void _restore(Version v) {
    setState(() {
      n.title = v.title;
      _title.text = v.title;
      for (final c in _ctl.values) {
        c.dispose();
      }
      for (final c in _ictl.values) {
        c.dispose();
      }
      _ctl.clear();
      _ictl.clear();
      n.blocks = v.blocks.map((b) => b.copy()).toList();
    });
    _touch();
  }

  Future<void> _addTag() async {
    final ctl = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый тег'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Например: работа'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Добавить')),
        ],
      ),
    );
    ctl.dispose();
    final tag = (t ?? '').trim().replaceAll('#', '');
    if (tag.isEmpty || n.tags.contains(tag)) return;
    setState(() => n.tags.add(tag));
    _touch();
  }
}
