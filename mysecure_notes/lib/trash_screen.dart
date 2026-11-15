import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Корзина: удалённые заметки хранятся 30 дней, затем стираются (и на сервере тоже).
class TrashScreen extends StatefulWidget {
  final Store store;
  const TrashScreen({super.key, required this.store});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  Store get s => widget.store;

  List<Note> get _list {
    final l = s.notes.where((n) => n.deleted && n.updatedAt > 1).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return l;
  }

  int _daysLeft(Note n) {
    final left = n.updatedAt + kTrashDays * 24 * 3600 * 1000 - nowMs();
    return (left / (24 * 3600 * 1000)).ceil().clamp(0, kTrashDays);
  }

  void _restore(Note n) {
    n.deleted = false;
    n.updatedAt = nowMs();
    s.changed();
    setState(() {});
    toast(context, 'Заметка восстановлена');
  }

  void _purge(Note n) {
    n.updatedAt = 1; // при ближайшей синхронизации будет стёрта и на сервере
    s.changed();
    setState(() {});
  }

  Future<void> _emptyAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить корзину?'),
        content: const Text('Все заметки из корзины будут стёрты безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очистить')),
        ],
      ),
    );
    if (ok != true) return;
    for (final n in _list) {
      n.updatedAt = 1;
    }
    s.changed();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Корзина'), actions: [
        if (l.isNotEmpty)
          IconButton(tooltip: 'Очистить', onPressed: _emptyAll, icon: const Icon(Icons.delete_sweep_outlined)),
      ]),
      body: l.isEmpty
          ? const Center(child: Text('Корзина пуста'))
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Заметки хранятся $kTrashDays дней, потом стираются.',
                    style: TextStyle(color: Pal.secondary(context))),
              ),
              for (final n in l)
                ListTile(
                  title: Text(n.title.isEmpty ? 'Без названия' : n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${n.preview(60)}\nУдалена ${fmtDate(n.updatedAt)} · осталось дней: ${_daysLeft(n)}',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Восстановить', onPressed: () => _restore(n), icon: const Icon(Icons.restore)),
                    IconButton(tooltip: 'Удалить навсегда', onPressed: () => _purge(n), icon: const Icon(Icons.delete_forever_outlined)),
                  ]),
                ),
            ]),
    );
  }
}
