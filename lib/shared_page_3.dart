// ▸ Часть shared_page.dart: Раздел «Общая папка»: группы, приглашения, участники  [содержит: _GroupScreenState, MembersScreen, _MembersScreenState]
part of 'shared_page.dart';


class _GroupScreenState extends State<GroupScreen> {
  Store get s => widget.store;
  Group get g => widget.group;
  bool get _owner => g.owner == s.settings.profileId;

  @override
  void initState() {
    super.initState();
    // вход в папку обновляет «последний онлайн»
    Groups.putProfile(Groups.remoteOf(g), g, s).catchError((Object _) {});
  }

  void _showProfile() {
    final id = g.memberId(s.settings.profileId);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Мой профиль в группе'),
        content: SelectableText('Имя: ${g.myName.isEmpty ? s.author : g.myName}\n'
            'Полный идентификатор:\n$id\n'
            'Права: ${_owner ? 'создатель' : rightsName(g.rights)}'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      ),
    );
  }

  void _newNote() {
    if (g.viewOnly) {
      toast(context, 'У вас режим «только просмотр»');
      return;
    }
    final n = Note.create(s.author, s.profileId, g.vault);
    s.notes.add(n);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EditorScreen(store: s, note: n)));
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content: const Text('Общие заметки и чат этой группы будут удалены с этого устройства. '
            'На сервере они останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok != true) return;
    await Groups.leave(s, g);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(g.name.isEmpty ? 'Общая папка' : g.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'invite') showInviteDialog(context, g);
                if (v == 'members') {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MembersScreen(store: s, group: g)));
                }
                if (v == 'profile') _showProfile();
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'profile', child: Text('Мой профиль')),
                if (!g.removed && _owner)
                  const PopupMenuItem(value: 'invite', child: Text('Копировать приглашение')),
                const PopupMenuItem(value: 'members', child: Text('Участники')),
                const PopupMenuItem(value: 'leave', child: Text('Выйти из группы')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Чат'), Tab(text: 'Заметки')]),
        ),
        body: g.removed
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Создатель удалил вас из этой группы. Её можно покинуть в меню.',
                        textAlign: TextAlign.center)))
            : TabBarView(children: [
                ChatPage(store: s, group: g),
                Stack(children: [
                  NotesList(
                    store: s,
                    filter: 'vault:${g.vault}',
                    tag: null,
                    home: false,
                    onClearTag: () {},
                  ),
                  Fab(onPressed: _newNote),
                ]),
              ]),
      ),
    );
  }
}

/// Участники группы. Создатель может ограничить редактирование и удалить участника.
class MembersScreen extends StatefulWidget {
  final Store store;
  final Group group;
  const MembersScreen({super.key, required this.store, required this.group});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Map<String, dynamic>> _list = [];
  Set<String> _ro = {};
  bool _loading = true;
  String? _err;

  Group get g => widget.group;
  bool get _owner => g.owner == widget.store.settings.profileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Groups.members(g);
      final ro = await Groups.readonlyIds(g);
      if (mounted) {
        setState(() {
          _list = l;
          _ro = ro;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    }
  }

  String _online(Object? v) {
    final ms = v is int ? v : 0;
    return ms == 0 ? 'онлайн: нет данных' : 'онлайн: ${fmtDate(ms)}';
  }

  Future<void> _toggleRo(String id, bool v) async {
    try {
      await Groups.setAcl(g, widget.store, readonlyId: id, readonly: v);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _remove(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «$name» из группы?'),
        content: const Text('Участник потеряет доступ в приложении. Если у него остался ключ '
            'и пароль WebDAV, то для полной защиты создайте новую папку с новым ключом.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Groups.setAcl(g, widget.store, remove: id);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.store.settings.profileId;
    return Scaffold(
      appBar: AppBar(title: const Text('Участники')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : ListView(children: [
                  for (final m in _list)
                    ListTile(
                      leading: Avatar((m['name'] ?? '?').toString(), (m['color'] ?? 0xFF007AFF) as int),
                      title: Text('${m['name'] ?? ''}'
                          '${m['uuid'] == g.owner ? ' · создатель' : ''}'
                          '${m['uuid'] == g.memberId(me) ? ' · вы' : ''}'),
                      subtitle: Text(
                          '${_online(m['lastSeen'])}'
                          '${_ro.contains(m['uuid']) ? ' · только чтение' : ''}',
                          style: const TextStyle(fontSize: 12)),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('${m['name'] ?? ''}'),
                          content: SelectableText('Полный идентификатор:\n${m['uuid']}\n\n'
                              'Права: ${m['rights'] == 'owner' ? 'создатель' : rightsName('${m['rights'] ?? 'edit'}')}\n'
                              'Последний онлайн: ${_online(m['lastSeen'])}'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))
                          ],
                        ),
                      ),
                      trailing: _owner && m['uuid'] != g.memberId(me)
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Только чтение',
                                icon: Icon(_ro.contains(m['uuid']) ? Icons.edit_off : Icons.edit_outlined),
                                onPressed: () => _toggleRo('${m['uuid']}', !_ro.contains(m['uuid'])),
                              ),
                              IconButton(
                                tooltip: 'Удалить',
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: () => _remove('${m['uuid']}', '${m['name']}'),
                              ),
                            ])
                          : null,
                    ),
                  if (!_owner)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Права участников меняет создатель папки.'),
                    ),
                ]),
    );
  }
}