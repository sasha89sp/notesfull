import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Комментарии к общей заметке: отдельные зашифрованные файлы, без правки,
/// автор удаляет в течение 5 минут, автор заметки — в любой момент.
class CommentsView extends StatefulWidget {
  final Store store;
  final Note note;
  const CommentsView({super.key, required this.store, required this.note});
  @override
  State<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<CommentsView> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String _slug(String s) {
    final a = s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return a.isEmpty ? 'user' : a;
  }

  void _send() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    final s = widget.store;
    final now = DateTime.now();
    final id = newId();
    final file =
        '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}_${_slug(s.author)}_$id.enc';
    s.comments.add(Comment(
      id: id,
      noteId: widget.note.id,
      authorId: s.profileId,
      author: s.author,
      at: nowMs(),
      text: text,
      file: file,
    ));
    _ctl.clear();
    s.commentsChanged();
    setState(() {});
  }

  bool _canDelete(Comment c) {
    final s = widget.store;
    if (c.deleted) return false;
    final mine = c.authorId == s.profileId;
    final noteOwner = widget.note.authorId == s.profileId;
    final fresh = nowMs() - c.at < 5 * 60 * 1000;
    return (mine && fresh) || noteOwner;
  }

  void _delete(Comment c) {
    c.deleted = true;
    c.text = '';
    c.delSynced = false;
    widget.store.commentsChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.comments
        .where((c) => c.noteId == widget.note.id)
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Комментарии'),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Пока нет комментариев',
              style: TextStyle(color: Pal.secondary(context))),
        ),
      for (final c in list)
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(c.author,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(fmtDate(c.at),
                  style: TextStyle(color: Pal.secondary(context), fontSize: 12)),
              const Spacer(),
              if (_canDelete(c))
                InkWell(
                  onTap: () => _delete(c),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: Pal.secondary(context)),
                ),
            ]),
            const SizedBox(height: 4),
            c.deleted
                ? Text('[Комментарий удалён]',
                    style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Pal.secondary(context)))
                : Text(c.text),
          ]),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ctl,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Написать комментарий'),
          ),
        ),
        IconButton(onPressed: _send, icon: const Icon(Icons.send)),
      ]),
      const SizedBox(height: 24),
    ]);
  }
}
