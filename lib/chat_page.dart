import 'dart:async';
import 'package:flutter/material.dart';
import 'hub.dart';
import 'models.dart';
import 'store.dart';
import 'sync.dart';
import 'widgets.dart';

/// Модуль «Чаты»: общий чат группы/семьи. Сообщения шифруются семейным ключом,
/// участники могут быть подключены к разным WebDAV (см. настройки → Общая группа).
class ChatPage extends StatefulWidget {
  final Store store;
  const ChatPage({super.key, required this.store});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _loaded = false;
  bool _polling = false;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    s.ensureChat().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_polling || s.syncing) return;
    _polling = true;
    try {
      await SyncService.chatOnly(s);
    } catch (_) {
      // сеть недоступна — повторим при следующем опросе
    } finally {
      _polling = false;
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await s.sendChat('general', t);
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _actions(ChatMsg m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('Сохранить как заметку'),
            onTap: () {
              Navigator.pop(ctx);
              Hub.noteFromText(s, m.text);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Заметка создана')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Добавить в календарь'),
            onTap: () async {
              Navigator.pop(ctx);
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
              Hub.eventFromText(s, m.text, DateTime(d.year, d.month, d.day, t.hour, t.minute));
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Событие добавлено')));
              }
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = s.settings;
    final hasKey = st.famKey.isNotEmpty || st.familyPass.isNotEmpty;
    if (!st.syncConfigured && !st.groupConfigured) {
      return const _Hint('Чат работает через общую группу. Подключите хранилище или '
          'общую группу в Настройки → Общая группа.');
    }
    if (!hasKey) {
      return const _Hint('Нужен семейный ключ: создайте семью или получите доступ от '
          'владельца (Настройки → Семья).');
    }
    final msgs = s.chat.where((m) => m.room == 'general').toList();
    final sec = Pal.secondary(context);
    return Column(children: [
      Expanded(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : msgs.isEmpty
                ? Center(child: Text('Сообщений пока нет', style: TextStyle(color: sec)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m = msgs[i];
                      final mine = m.authorId == st.profileId;
                      final cs = Theme.of(context).colorScheme;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () => _actions(m),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: mine ? cs.primary : Pal.card(context),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine)
                                  Text(m.author,
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w600, color: sec)),
                                Text(m.text,
                                    style: TextStyle(color: mine ? cs.onPrimary : null)),
                                Text(
                                  '${fmtTime(DateTime.fromMillisecondsSinceEpoch(m.at))}${m.synced ? '' : ' · не отправлено'}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: mine ? cs.onPrimary.withOpacity(0.7) : sec),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Сообщение'),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _send),
          ]),
        ),
      ),
    ]);
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center)));
}
