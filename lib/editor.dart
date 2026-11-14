import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'comments_view.dart';
import 'groups.dart';
import 'hub.dart';
import 'md_editor.dart';
import 'media.dart';
import 'models.dart';
import 'store.dart';
import 'table_screen.dart';
import 'util.dart';
import 'widgets.dart';

class EditorScreen extends StatefulWidget {
  final Store store;
  final Note note;
  final bool embedded; // внутри трёхколоночного десктопного вида
  final VoidCallback? onClosed;
  const EditorScreen(
      {super.key,
      required this.store,
      required this.note,
      this.embedded = false,
      this.onClosed});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _title;
  final Map<String, TextEditingController> _ctl = {};
  final Map<CheckItem, TextEditingController> _ictl = {};
  Timer? _deb;
  late String _origSig;
  late String _origTitle;
  late List<Block> _origBlocks;

  Note get n => widget.note;
  Store get s => widget.store;

  String _sig() => jsonEncode({
        't': n.title,
        'b': n.blocks.map((b) => b.toJson()).toList(),
      });

  @override
  void initState() {
    super.initState();
    if (n.blocks.isEmpty && n.title.isEmpty) {
      n.blocks.add(Block(type: 'text'));
    }
    _title = TextEditingController(text: n.title);
    _origTitle = n.title;
    _origBlocks = n.blocks.map((b) => b.copy()).toList();
    _origSig = _sig();
  }

  @override
  void dispose() {
    _deb?.cancel();
    final empty = n.title.trim().isEmpty && n.blocks.every((b) => b.isEmpty);
    if (empty && n.syncedAt == 0 && n.history.isEmpty && !n.deleted) {
      s.notes.remove(n);
    } else if (_sig() != _origSig) {
      final hadContent =
          _origTitle.isNotEmpty || _origBlocks.any((b) => !b.isEmpty);
      if (hadContent) {
        n.history.insert(
            0, Version(at: nowMs(), title: _origTitle, blocks: _origBlocks));
        if (n.history.length > 8) {
          n.history.removeRange(8, n.history.length);
        }
      }
    }
    final store = s;
    Future.microtask(store.changed);
    _title.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final c in _ictl.values) {
      c.dispose();
    }
    super.dispose();
  }

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
          ? await saveBytes('$safe.zip', await Jex.exportMarkdown(s, [n]))
          : await saveBytes('$safe.md',
              utf8.encode('# ${n.title}\n\n${Jex.bodyOf(n, (b) => null)}\n'));
      if (ok && mounted) toast(context, 'Экспортировано');
    } catch (e) {
      if (mounted) toast(context, 'Ошибка экспорта: $e');
    }
  }

  void _menu(String v) {
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(children: [
            Icon(n.isGroup ? Icons.group_outlined : Icons.lock_outline,
                size: 18, color: Pal.secondary(context)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _vaults().any((v) => v.key == n.vault) ? n.vault : 'personal',
              underline: const SizedBox.shrink(),
              items: [
                for (final v in _vaults())
                  DropdownMenuItem(value: v.key, child: Text(v.value)),
              ],
              onChanged: _ro
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => n.vault = v);
                      _touch();
                    },
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(children: [
            for (final t in n.tags)
              TagChip(t, onDelete: () {
                setState(() => n.tags.remove(t));
                _touch();
              }),
            ActionChip(
              label: const Text('+ тег'),
              onPressed: _addTag,
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Создал: ${n.author.isEmpty ? '—' : n.author} · ${fmtDate(n.createdAt)}\n'
            'Изменено: ${n.editor.isEmpty ? '—' : n.editor} · ${fmtDate(n.updatedAt)}',
            style: TextStyle(color: Pal.secondary(context), fontSize: 12),
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
                    color: item.done ? Pal.secondary(context) : null,
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

  Widget _addBtn(IconData icon, String label, VoidCallback f) {
    return TextButton.icon(
      icon: Icon(icon, size: 20),
      label: Text(label),
      onPressed: f,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            icon: Icon(n.favorite ? Icons.star : Icons.star_border),
            onPressed: () => _menu('fav'),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'event', child: Text('Добавить в календарь')),
              PopupMenuItem(value: 'history', child: Text('История версий')),
              PopupMenuItem(value: 'md', child: Text('Экспорт в Markdown')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: ReorderableListView(
        header: _header(),
        footer: n.isGroup
            ? CommentsView(store: s, note: n)
            : const SizedBox(height: 16),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        buildDefaultDragHandles: false,
        onReorder: (oldIndex, newIndex) {
          var ni = newIndex;
          setState(() {
            if (ni > oldIndex) ni -= 1;
            final b = n.blocks.removeAt(oldIndex);
            n.blocks.insert(ni, b);
          });
          _touch();
        },
        children: [
          for (var i = 0; i < n.blocks.length; i++) _blockCard(i, n.blocks[i]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _addBtn(Icons.text_fields, 'Текст', () => _addBlock('text')),
              _addBtn(Icons.checklist, 'Чек-лист', () => _addBlock('checklist')),
              _addBtn(Icons.table_chart_outlined, 'Таблица',
                  () => _addBlock('table')),
              _addBtn(Icons.mic_none, 'Голос', () => _addBlock('voice')),
              _addBtn(Icons.image_outlined, 'Фото', _addImage),
              _addBtn(Icons.attach_file, 'Файл', _addFile),
              _addBtn(Icons.format_quote, 'Цитата', () => _addBlock('quote')),
              _addBtn(Icons.code, 'Код', () => _addBlock('code')),
            ],
          ),
        ),
      ),
    );
  }
}
