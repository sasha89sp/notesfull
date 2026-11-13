import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_page.dart';
import 'editor.dart';
import 'groups.dart';
import 'models.dart';
import 'notes_page.dart';
import 'remote.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Модуль «Общая папка»: список групп (каждая — своя папка на своём WebDAV со своим
/// ключом), создание и вход по приглашению.
class SharedPage extends StatefulWidget {
  final Store store;
  const SharedPage({super.key, required this.store});

  @override
  State<SharedPage> createState() => _SharedPageState();
}

class _SharedPageState extends State<SharedPage> {
  Store get s => widget.store;

  Future<void> _create() async {
    final st = s.settings;
    if (st.storage != 'webdav' || !st.syncConfigured) {
      toast(context, 'Чтобы создать общую папку, подключитесь к WebDAV (Настройки)');
      return;
    }
    final g = await showDialog<Group>(
      context: context,
      builder: (_) => _CreateDialog(store: s),
    );
    if (g == null || !mounted) return;
    setState(() {});
    s.syncAll();
    await showInviteDialog(context, g);
  }

  Future<void> _join() async {
    final c = TextEditingController();
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if ((d?.text ?? '').trim().startsWith('asrbox-g1')) c.text = d!.text!.trim();
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Войти в общую группу'),
        content: TextField(
          controller: c,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(labelText: 'Вставьте приглашение'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Войти')),
        ],
      ),
    );
    c.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    try {
      final g = await Groups.join(s, text);
      if (mounted) {
        setState(() {});
        toast(context, 'Вы в группе «${g.name}»');
      }
      s.syncAll();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final groups = s.settings.groups;
        final sec = Pal.secondary(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                    'Общая папка — место для чата и совместных заметок. Создайте её на своём '
                    'WebDAV или войдите в чужую по приглашению. У каждой группы свой ключ шифрования.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sec)),
              ),
            for (final g in groups)
              AppCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => GroupScreen(store: s, group: g))),
                child: Row(children: [
                  Icon(Icons.folder_shared_outlined,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.name.isEmpty ? 'Общая папка' : g.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                      Text(
                          g.removed
                              ? 'Вас удалили из группы'
                              : '${g.owner == s.settings.profileId ? 'Создатель' : 'Участник'}'
                                  '${g.readOnly ? ' · только чтение' : ''} · ${g.folder}',
                          style: TextStyle(color: g.removed ? Pal.error(context) : sec, fontSize: 12)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: sec),
                ]),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(groups.isEmpty ? 'Создать общую папку' : 'Создать ещё одну папку'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _join,
              icon: const Icon(Icons.login),
              label: Text(groups.isEmpty ? 'Войти в общую группу' : 'Войти ещё в одну группу'),
            ),
          ],
        );
      },
    );
  }
}

/// «Копировать приглашение»: в открытом виде или зашифровано (рекомендуется).
Future<void> showInviteDialog(BuildContext context, Group g) async {
  Future<void> copy(bool enc) async {
    final text = await Groups.invite(g, encrypted: enc);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      Navigator.pop(context);
      toast(context, 'Приглашение скопировано');
    }
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Копировать приглашение'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('В приглашении: адрес, логин и пароль WebDAV, папка и ключ шифрования. '
            'Передавайте только тем, кому доверяете.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => copy(true),
          child: const Text('Зашифровано · рекомендуется'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text('Получатель не увидит логин и пароль от WebDAV: приложение подставит их само.',
              style: TextStyle(fontSize: 12)),
        ),
        OutlinedButton(
          onPressed: () => copy(false),
          child: const Text('В открытом виде'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text('Строка видна полностью, её можно прочитать.', style: TextStyle(fontSize: 12)),
        ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
    ),
  );
}

class _CreateDialog extends StatefulWidget {
  final Store store;
  const _CreateDialog({required this.store});

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _name = TextEditingController();
  final _newFolder = TextEditingController();
  final _phrase = TextEditingController();
  String? _picked; // существующая папка
  bool _own = false;
  bool _busy = false;
  String? _err;
  late final Future<List<String>> _dirs;

  @override
  void initState() {
    super.initState();
    final st = widget.store.settings;
    _dirs = Dav(st.url, st.user, st.pass).listDirs('/').then((l) {
      l.removeWhere((e) => e.startsWith('.'));
      l.sort();
      return l;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _newFolder.dispose();
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    final folder = _picked ?? _newFolder.text.trim();
    if (_name.text.trim().isEmpty) return setState(() => _err = 'Введите название');
    if (folder.isEmpty) return setState(() => _err = 'Выберите папку или введите имя новой');
    if (_own && _phrase.text.length < 6) {
      return setState(() => _err = 'Ключ: минимум 6 символов');
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final g = await Groups.create(widget.store,
          name: _name.text, folder: folder, phrase: _own ? _phrase.text : null);
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая общая папка'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            const Text('Папка на сервере', style: TextStyle(fontWeight: FontWeight.w600)),
            FutureBuilder<List<String>>(
              future: _dirs,
              builder: (_, snap) {
                final dirs = snap.data ?? const <String>[];
                return Column(children: [
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  for (final d in dirs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_picked == d ? Icons.radio_button_checked : Icons.radio_button_off),
                      title: Text(d),
                      onTap: () => setState(() => _picked = d),
                    ),
                ]);
              },
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_picked == null ? Icons.radio_button_checked : Icons.radio_button_off),
              title: const Text('Новая папка'),
              onTap: () => setState(() => _picked = null),
            ),
            if (_picked == null)
              TextField(controller: _newFolder, decoration: const InputDecoration(labelText: 'Имя новой папки')),
            const SizedBox(height: 12),
            const Text('Ключ шифрования', style: TextStyle(fontWeight: FontWeight.w600)),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Сгенерировать')),
                ButtonSegment(value: true, label: Text('Свой')),
              ],
              selected: {_own},
              onSelectionChanged: (v) => setState(() => _own = v.first),
            ),
            if (_own)
              TextField(
                  controller: _phrase,
                  decoration: const InputDecoration(labelText: 'Ваш ключ (фраза)')),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_err!, style: TextStyle(color: Pal.error(context))),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: _busy ? null : _ok, child: const Text('ОК')),
      ],
    );
  }
}

/// Внутри группы: Чат и Заметки (полный функционал заметок с комментариями).
class GroupScreen extends StatefulWidget {
  final Store store;
  final Group group;
  const GroupScreen({super.key, required this.store, required this.group});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  Store get s => widget.store;
  Group get g => widget.group;
  bool get _owner => g.owner == s.settings.profileId;

  void _newNote() {
    if (g.readOnly) {
      toast(context, 'Создатель ограничил вам редактирование');
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
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => [
                if (!g.removed)
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
                          '${m['uuid'] == me ? ' · вы' : ''}'),
                      subtitle: _ro.contains(m['uuid']) ? const Text('только чтение') : null,
                      trailing: _owner && m['uuid'] != me
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
