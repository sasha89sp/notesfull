import 'dart:convert';
import 'package:flutter/material.dart';
import 'applog.dart';
import 'models.dart';
import 'store.dart';
import 'synchist.dart';
import 'util.dart';
import 'widgets.dart';

/// Настройки → История синхронизации.
class SyncHistoryScreen extends StatelessWidget {
  final Store store;
  const SyncHistoryScreen({super.key, required this.store});

  Future<void> _export(BuildContext context) async {
    final b = StringBuffer('История синхронизации\n\n');
    for (final r in store.history.reversed) {
      b.writeln(r.toText());
    }
    final ok = await saveBytes('sync_history.txt', utf8.encode(b.toString()));
    if (ok && context.mounted) toast(context, 'Лог сохранён');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final list = store.history.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('История синхронизации'),
            actions: [
              IconButton(
                tooltip: 'Экспорт в файл',
                icon: const Icon(Icons.ios_share),
                onPressed: list.isEmpty ? null : () => _export(context),
              ),
              IconButton(
                tooltip: 'Очистить',
                icon: const Icon(Icons.delete_outline),
                onPressed: list.isEmpty ? null : store.clearHistory,
              ),
            ],
          ),
          body: list.isEmpty
              ? const Center(child: Text('Синхронизаций ещё не было'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final color = r.status == 'ok'
                        ? Pal.success(context)
                        : r.status == 'cancelled'
                            ? Pal.secondary(context)
                            : Pal.error(context);
                    return ExpansionTile(
                      leading: Icon(
                          r.status == 'ok'
                              ? Icons.check_circle
                              : r.status == 'cancelled'
                                  ? Icons.cancel_outlined
                                  : Icons.error_outline,
                          color: color),
                      title: Text('${r.when} — ${r.statusText}'),
                      subtitle: Text(
                          'Куда: ${r.targets.isEmpty ? '—' : r.targets.join(', ')}',
                          style: const TextStyle(fontSize: 12)),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Отправлено: ${r.sentText}'),
                        const SizedBox(height: 4),
                        Text('Получено: ${r.receivedText}'),
                        if (r.conflicts > 0) ...[
                          const SizedBox(height: 4),
                          Text('Конфликтов: ${r.conflicts}'),
                        ],
                        if (r.log.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Журнал операции',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Pal.secondary(context))),
                          for (final l in r.log)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('• $l',
                                  style: const TextStyle(fontSize: 13)),
                            ),
                        ],
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Настройки → Отладка / диагностика.
class LogScreen extends StatelessWidget {
  final Store store;
  const LogScreen({super.key, required this.store});

  Future<void> _export(BuildContext context) async {
    final ok =
        await saveBytes('mysecure_log.txt', utf8.encode(AppLog.I.exportText()));
    if (ok && context.mounted) toast(context, 'Журнал сохранён');
  }

  Color _col(BuildContext c, String l) {
    switch (l) {
      case 'E':
        return Pal.error(c);
      case 'W':
        return const Color(0xFFFF9500);
      default:
        return Pal.secondary(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppLog.I,
      builder: (context, _) {
        final list = AppLog.I.entries.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Диагностика'),
            actions: [
              IconButton(
                tooltip: 'Экспорт журнала',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _export(context),
              ),
              IconButton(
                tooltip: 'Очистить',
                icon: const Icon(Icons.delete_outline),
                onPressed: AppLog.I.clear,
              ),
            ],
          ),
          body: Column(children: [
            SwitchListTile(
              title: const Text('Подробное логирование'),
              subtitle: const Text('Больше записей: полезно при поиске причины сбоя'),
              value: store.settings.verboseLog,
              onChanged: (v) {
                store.settings.verboseLog = v;
                AppLog.I.verbose = v;
                store.saveSettings();
                store.refresh();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Журнал пуст'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = list[i];
                        return ListTile(
                          dense: true,
                          leading: Text(e.level,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _col(context, e.level))),
                          title: Text(e.msg,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              '${fmtDay(e.at)} ${two(e.at.hour)}:${two(e.at.minute)}:${two(e.at.second)} · ${e.module}',
                              style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
