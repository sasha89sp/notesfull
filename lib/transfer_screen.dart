import 'package:flutter/material.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';
import 'widgets.dart';

/// Подробный журнал процессов синхронизации: этапы, каждый запрос, объём, время, скорость.
class TransferScreen extends StatelessWidget {
  final Store store;
  const TransferScreen({super.key, required this.store});

  String _t(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String x(int v) => v.toString().padLeft(2, '0');
    return '${x(d.hour)}:${x(d.minute)}:${x(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Процессы синхронизации')),
      body: AnimatedBuilder(
        animation: Listenable.merge([store, Net.tick]),
        builder: (context, _) {
          final (u, d) = Net.speed();
          final p = store.progress;
          final list = Net.log.reversed.take(400).toList();
          final sec = Pal.secondary(context);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store.syncing ? store.progressText : 'Синхронизация не выполняется',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (store.syncing) LinearProgressIndicator(value: p),
                const SizedBox(height: 8),
                Text(
                    '${p == null ? '' : '${(p * 100).round()}% · '}'
                    '↓ ${Net.fmtSpeed(d)}   ↑ ${Net.fmtSpeed(u)}',
                    style: TextStyle(color: sec)),
                Text('Всего: получено ${Net.fmtSize(Net.down)}, отправлено ${Net.fmtSize(Net.up)}',
                    style: TextStyle(color: sec, fontSize: 12)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Журнал пуст'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final stage = e.op == 'этап';
                        final bad = e.result.startsWith('ошибка') ||
                            (e.result.startsWith('HTTP') && !e.result.startsWith('HTTP 2') && !e.result.startsWith('HTTP 404'));
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              stage
                                  ? Icons.flag_outlined
                                  : e.up > 0
                                      ? Icons.arrow_upward
                                      : e.down > 0
                                          ? Icons.arrow_downward
                                          : Icons.swap_vert,
                              size: 18,
                              color: bad ? Pal.error(context) : null),
                          title: Text(e.target, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              stage
                                  ? _t(e.at)
                                  : '${_t(e.at)} · ${e.op} · '
                                      '${e.up > 0 ? '↑ ${Net.fmtSize(e.up)} ' : ''}'
                                      '${e.down > 0 ? '↓ ${Net.fmtSize(e.down)} ' : ''}'
                                      '· ${e.ms} мс · ${e.result}',
                              style: TextStyle(fontSize: 11, color: bad ? Pal.error(context) : sec)),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}
