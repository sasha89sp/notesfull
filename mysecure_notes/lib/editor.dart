import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'pdf_export.dart';
import 'comments_view.dart';
import 'groups.dart';
import 'hub.dart';
import 'ics_block.dart';
import 'md_editor.dart';
import 'media.dart';
import 'models.dart';
import 'store.dart';
import 'table_screen.dart';
import 'util.dart';
import 'widgets.dart';

part 'editor_2.dart';
part 'editor_3.dart';
part 'editor_4.dart';


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

  bool _view = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            tooltip: _view ? 'Режим правки' : 'Режим просмотра',
            icon: Icon(_view ? Icons.edit_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _view = !_view),
          ),
          IconButton(
            tooltip: 'О заметке: хранилище, теги, даты',
            icon: const Icon(Icons.info_outline),
            onPressed: _showMeta,
          ),
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
              PopupMenuItem(value: 'pdf', child: Text('Экспорт в PDF')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: _view ? _viewBody() : ReorderableListView(
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
      bottomNavigationBar: _view ? null : SafeArea(
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
              _addBtn(Icons.event_note_outlined, 'Календарь', () => _addBlock('ics')),
              _addBtn(Icons.format_quote, 'Цитата', () => _addBlock('quote')),
              _addBtn(Icons.code, 'Код', () => _addBlock('code')),
            ],
          ),
        ),
      ),
    );
  }}