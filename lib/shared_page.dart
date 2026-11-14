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

String rightsName(String r) =>
    r == 'view' ? 'только просмотр' : r == 'own' ? 'свои файлы и комментарии' : 'полное редактирование';

class _SharedPageState extends State<SharedPage> {
  Store get s => widget.store;

  Future<void> _create() async {
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
    final nm = TextEditingController(text: s.author);
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if ((d?.text ?? '').trim().startsWith('asrbox-g1')) c.text = d!.text!.trim();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Получить приглашение'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              maxLines: 4,
              minLines: 2,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(labelText: 'Вставьте приглашение'),
            ),
            TextField(
              controller: nm,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(
                  labelText: 'Ваше имя (обязательно)',
                  helperText: 'Без имени доступ не выдаётся'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            TextButton(
                onPressed: c.text.trim().isEmpty || nm.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Войти')),
          ],
        ),
      ),
    );
    final text = c.text;
    final name = nm.text;
    c.dispose();
    nm.dispose();
    if (ok != true || !mounted) return;
    try {
      final g = await Groups.join(s, text, name);
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
                                  '${g.viewOnly ? ' · только просмотр' : ''} · ${g.folder}',
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

/// «Копировать приглашение»: права, разовая или многоразовая ссылка, вид (зашифрованно — рекомендуется).
Future<void> showInviteDialog(BuildContext context, Group g) async {
  var rights = 'edit';
  var single = true;
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Future<void> copy(bool enc) async {
          set(() => busy = true);
          try {
            final text = await Groups.makeInvite(g, encrypted: enc, rights: rights, single: single);
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) {
              Navigator.pop(ctx);
              toast(context, 'Приглашение скопировано');
            }
          } catch (e) {
            if (ctx.mounted) {
              set(() => busy = false);
              toast(ctx, 'Не удалось создать приглашение: $e');
            }
          }
        }

        return AlertDialog(
          title: const Text('Копировать приглашение'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('В приглашении: логин и пароль WebDAV, папка, ключ шифрования и уникальный ID. '
                  'Передавайте только тем, кому доверяете.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              const Text('Права', style: TextStyle(fontWeight: FontWeight.w600)),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Только просмотр'),
                value: 'view',
                groupValue: rights,
                onChanged: (v) => set(() => rights = v!),
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Полное редактирование любого файла'),
                subtitle: const Text('в каждом файле видно, кто его изменил', style: TextStyle(fontSize: 11)),
                value: 'edit',
                groupValue: rights,
                onChanged: (v) => set(() => rights = v!),
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Свои файлы и комментарии'),
                subtitle: const Text('создаёт и правит только свои, комментирует чужие', style: TextStyle(fontSize: 11)),
                value: 'own',
                groupValue: rights,
                onChanged: (v) => set(() => rights = v!),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Разовая')),
                  ButtonSegment(value: false, label: Text('Многоразовая')),
                ],
                selected: {single},
                onSelectionChanged: (v) => set(() => single = v.first),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                    single
                        ? 'По ссылке сможет войти только один человек.'
                        : 'По ссылке смогут войти несколько человек.',
                    style: const TextStyle(fontSize: 12)),
              ),
              FilledButton(
                onPressed: busy ? null : () => copy(true),
                child: const Text('Зашифровано · рекомендуется'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Text('Получатель не увидит логин и пароль от WebDAV: приложение подставит их само.',
                    style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => copy(false),
                child: const Text('В открытом виде'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text('Строка видна полностью, её можно прочитать.', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
        );
      },
    ),
  );
}

/// Файловый менеджер сервера: переходы по папкам, создание папки, выбор.
class _FolderPicker extends StatefulWidget {
  final Remote dav;
  final String start;
  const _FolderPicker({required this.dav, required this.start});

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late String _path;
  List<String> _dirs = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _path = widget.start.isEmpty ? '/' : widget.start;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final l = await widget.dav.listDirs(_path);
      l.removeWhere((e) => e.startsWith('.'));
      l.sort();
      if (mounted) {
        setState(() {
          _dirs = l;
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

  String _join(String n) => _path == '/' ? '/$n' : '$_path/$n';

  void _up() {
    if (_path == '/') return;
    final i = _path.lastIndexOf('/');
    _path = i <= 0 ? '/' : _path.substring(0, i);
    _load();
  }

  Future<void> _mk() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Имя')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    final n = c.text.trim().replaceAll('/', '');
    c.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await widget.dav.mkcolAll(_join(n));
      _path = _join(n);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        IconButton(onPressed: _path == '/' ? null : _up, icon: const Icon(Icons.arrow_upward)),
        Expanded(child: Text(_path, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: 'Создать папку', onPressed: _mk, icon: const Icon(Icons.create_new_folder_outlined)),
      ]),
      content: SizedBox(
        width: 360,
        height: 320,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? Center(child: Text(_err!, style: TextStyle(color: Pal.error(context))))
                : _dirs.isEmpty
                    ? const Center(child: Text('Вложенных папок нет'))
                    : ListView(children: [
                        for (final d in _dirs)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(d),
                            onTap: () {
                              _path = _join(d);
                              _load();
                            },
                          ),
                      ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, _path), child: const Text('Выбрать эту папку')),
      ],
    );
  }
}

class _CreateDialog extends StatefulWidget {
  final Store store;
  const _CreateDialog({required this.store});

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _path = TextEditingController();
  final _id = TextEditingController(text: Groups.stamp());
  final _phrase = TextEditingController();
  bool _own = false;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final st = widget.store.settings;
    if (st.storage == 'webdav' && st.syncConfigured) {
      // данные текущей авторизации подставляются сами, их можно изменить
      _url.text = st.url;
      _user.text = st.user;
      _pass.text = st.pass;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _user, _pass, _path, _id, _phrase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _browse() async {
    if (_url.text.trim().isEmpty) return setState(() => _err = 'Сначала укажите WebDAV-сервер');
    final r = Dav(_url.text.trim(), _user.text.trim(), _pass.text);
    final p = await showDialog<String>(
      context: context,
      builder: (_) => _FolderPicker(dav: r, start: _path.text.trim().startsWith('/') ? _path.text.trim() : '/'),
    );
    if (p != null) setState(() => _path.text = p);
  }

  Future<void> _ok() async {
    if (_name.text.trim().isEmpty) return setState(() => _err = 'Введите название');
    if (_path.text.trim().isEmpty) return setState(() => _err = 'Выберите папку или введите путь');
    if (_own && _phrase.text.length < 6) {
      return setState(() => _err = 'Ключ: минимум 6 символов');
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final g = await Groups.create(widget.store,
          name: _name.text,
          folder: _path.text,
          url: _url.text,
          user: _user.text,
          pass: _pass.text,
          id: _id.text,
          phrase: _own ? _phrase.text : null);
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
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 8),
            const Text('Сервер', style: TextStyle(fontWeight: FontWeight.w600)),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'WebDAV-сервер')),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Логин')),
            TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль')),
            const SizedBox(height: 10),
            const Text('Папка на сервере', style: TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _path,
                    decoration: const InputDecoration(labelText: 'Путь, например /Family')),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Открыть папку',
                  onPressed: _browse,
                  icon: const Icon(Icons.folder_open)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _id,
              decoration: InputDecoration(
                labelText: 'Уникальный ID',
                helperText: 'Дата и время с секундами; можно ввести свой',
                suffixIcon: IconButton(
                    tooltip: 'Сгенерировать заново',
                    onPressed: () => setState(() => _id.text = Groups.stamp()),
                    icon: const Icon(Icons.refresh)),
              ),
            ),
            const SizedBox(height: 10),
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
