import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'calendar_page.dart';
import 'chat_page.dart';
import 'desktop.dart';
import 'editor.dart';
import 'event_screen.dart';
import 'models.dart';
import 'notes_page.dart';
import 'pass_page.dart';
import 'pass_store.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'widgets.dart';

/// Главная оболочка: нижняя навигация (Главная, Заметки, Календарь, Пароли),
/// боковое меню, триггеры синхронизации, всплывающее напоминание на Windows.
class Shell extends StatefulWidget {
  final Store store;
  final PassStore pass;
  final void Function(String theme) onTheme;
  final Future<void> Function(bool picker) onLogout;
  const Shell(
      {super.key,
      required this.store,
      required this.pass,
      required this.onLogout,
      required this.onTheme});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  String _tab = 'home';
  final Set<String> _visited = {'home'};
  String _filter = 'all';
  String? _tag;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _conn;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.syncAll();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => s.syncAll());
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) s.schedSync();
    });
    if (Platform.isAndroid && !s.settings.wizardDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showPermissionWizard(context, s);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _conn?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) s.syncAll();
  }

  bool _on(String m) => s.settings.moduleOn(m);

  /// Активные разделы: отключённые модули не показываются и не загружаются.
  List<String> get _mods => [
        'home',
        if (_on('notes')) 'notes',
        if (_on('calendar')) 'calendar',
        if (_on('pass')) 'pass',
        if (_on('chat')) 'chat',
      ];

  void _go(String m) => setState(() {
        _tab = m;
        _visited.add(m);
      });

  String get _title {
    switch (_tab) {
      case 'notes':
        return _filterName();
      case 'calendar':
        return 'Календарь';
      case 'pass':
        return 'Пароли';
      case 'chat':
        return 'Чаты';
      default:
        return _filter == 'all' ? 'Главная' : _filterName();
    }
  }

  String _filterName() {
    switch (_filter) {
      case 'personal':
        return 'Личное';
      case 'family':
        return 'Семейное';
      case 'fav':
        return 'Избранное';
      default:
        return 'Заметки';
    }
  }

  void _newNote() {
    final n = Note.create(
        s.author, s.profileId, _filter == 'family' ? 'family' : 'personal');
    s.notes.add(n);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EditorScreen(store: s, note: n)));
  }

  void _newEvent({bool task = false}) {
    final e = CalEvent.create(DateTime.now(), task: task);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EventScreen(store: s, event: e, isNew: true)));
  }

  void _quickCreate() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('Новая заметка'),
            onTap: () {
              Navigator.pop(ctx);
              _newNote();
            },
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Новое событие'),
            onTap: () {
              Navigator.pop(ctx);
              _newEvent();
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Новая задача'),
            onTap: () {
              Navigator.pop(ctx);
              _newEvent(task: true);
            },
          ),
        ]),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback f,
      {bool selected = false}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.pop(context);
        f();
      },
    );
  }

  Widget _drawer() {
    final tags = <String>{};
    for (final n in (_on('notes') ? s.notes.where((n) => !n.deleted) : <Note>[])) {
      tags.addAll(n.tags);
    }
    final sortedTags = tags.toList()..sort();
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Expanded(
              child: ListView(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Avatar(s.author, s.settings.color, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.author,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text('МОДУЛИ',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          ),
          if (_on('notes'))
            _drawerItem(Icons.notes, 'Заметки', () {
              _go('notes');
              setState(() {
                _filter = 'all';
                _tag = null;
              });
            }, selected: _tab == 'notes'),
          if (_on('calendar'))
            _drawerItem(Icons.calendar_month_outlined, 'Календарь',
                () => _go('calendar'),
                selected: _tab == 'calendar'),
          if (_on('pass'))
            _drawerItem(Icons.key_outlined, 'Пароли', () => _go('pass'),
                selected: _tab == 'pass'),
          if (_on('chat'))
            _drawerItem(Icons.chat_bubble_outline, 'Чаты', () => _go('chat'),
                selected: _tab == 'chat'),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text('БИБЛИОТЕКА',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          ),
          if (_on('notes')) ...[
          _drawerItem(Icons.lock_outline, 'Личное', () {
                _go('notes');
                setState(() {
                  _filter = 'personal';
                  _tag = null;
                });
              }, selected: _tab == 'notes' && _filter == 'personal'),
          _drawerItem(Icons.group_outlined, 'Семейное', () {
                _go('notes');
                setState(() {
                  _filter = 'family';
                  _tag = null;
                });
              }, selected: _tab == 'notes' && _filter == 'family'),
          _drawerItem(Icons.star_border, 'Избранное', () {
                _go('notes');
                setState(() {
                  _filter = 'fav';
                  _tag = null;
                });
              }, selected: _tab == 'notes' && _filter == 'fav'),
          ],
          if (sortedTags.isNotEmpty) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('ТЕГИ',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
            ),
            for (final t in sortedTags)
              ListTile(
                leading: Icon(Icons.tag, color: tagColor(t)),
                title: Text(t),
                selected: _tag == t,
                onTap: () {
                  Navigator.pop(context);
                  _go('notes');
                  setState(() {
                    _filter = 'all';
                    _tag = t;
                  });
                },
              ),
          ],
          const Divider(),
          _drawerItem(Icons.settings_outlined, 'Настройки', () {
            Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    SettingsScreen(
              store: s, onTheme: widget.onTheme, onLogout: widget.onLogout)));
          }),
          ListTile(
            leading: Icon(Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            title: const Text('Переключить тему'),
            onTap: () {
              final dark = Theme.of(context).brightness == Brightness.dark;
              s.settings.theme = dark ? 'light' : 'dark';
              s.saveSettings();
              widget.onTheme(s.settings.theme);
            },
          ),
        ])),
          _syncPanel(),
        ]),
      ),
    );
  }

  void _syncNow() {
    if (!s.settings.syncConfigured && !s.settings.googleConfigured) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
              store: s, onTheme: widget.onTheme, onLogout: widget.onLogout)));
    } else {
      s.syncAll();
    }
  }

  /// Внизу бокового меню: кнопка синхронизации и итог последней.
  Widget _syncPanel() {
    final last = s.lastSync;
    final col = last == null
        ? Pal.secondary(context)
        : last.status == 'ok'
            ? Pal.success(context)
            : last.status == 'cancelled'
                ? Pal.secondary(context)
                : Pal.error(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Pal.border(context), width: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.syncing) ...[
          LinearProgressIndicator(value: s.progress),
          const SizedBox(height: 6),
          Text(s.progressText,
              style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: s.cancelSync, child: const Text('Отменить')),
        ] else
          FilledButton.icon(
            onPressed: _syncNow,
            icon: const Icon(Icons.sync),
            label: const Text('Синхронизировать'),
          ),
        const SizedBox(height: 8),
        if (last == null)
          Text('Синхронизаций ещё не было',
              style: TextStyle(fontSize: 12, color: Pal.secondary(context)))
        else
          Text('Последняя: ${last.when}\nСтатус: ${last.statusText}',
              style: TextStyle(fontSize: 12, color: col)),
      ]),
    );
  }

  /// Страницы строятся лениво: модуль загружается при первом открытии,
  /// а отключённый не загружается вовсе.
  Widget _page(String m) {
    if (m != _tab && !_visited.contains(m)) return const SizedBox.shrink();
    switch (m) {
      case 'home':
        return _on('notes')
            ? NotesList(
                key: const ValueKey('home'),
                store: s,
                filter: _filter,
                tag: _tag,
                home: true,
                onClearTag: () => setState(() => _tag = null))
            : _ModulesHome(mods: _mods, onOpen: _go);
      case 'notes':
        return NotesList(
            key: const ValueKey('notes'),
            store: s,
            filter: _filter,
            tag: _tag,
            home: false,
            onClearTag: () => setState(() => _tag = null));
      case 'calendar':
        return CalendarPage(store: s);
      case 'pass':
        return _tab == 'pass'
            ? PassPage(store: s, pass: widget.pass)
            : const SizedBox.shrink();
      case 'chat':
        return ChatPage(store: s);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _body() {
    final mods = _mods;
    if (!mods.contains(_tab)) _tab = 'home';
    return IndexedStack(
        index: mods.indexOf(_tab), children: [for (final m in mods) _page(m)]);
  }

  static const _icons = {
    'home': Icons.home_outlined,
    'notes': Icons.notes,
    'calendar': Icons.calendar_month_outlined,
    'pass': Icons.key_outlined,
    'chat': Icons.chat_bubble_outline,
  };
  static const _names = {
    'home': 'Главная',
    'notes': 'Заметки',
    'calendar': 'Календарь',
    'pass': 'Пароли',
    'chat': 'Чаты',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CalEvent?>(
      valueListenable: Desktop.I.alert,
      builder: (context, alert, _) {
        if (alert != null) return _AlertView(event: alert);
        return AnimatedBuilder(
          animation: s,
          builder: (context, _) => Scaffold(
            appBar: AppBar(
              title: Text(_title,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700)),
              actions: [
                if (s.syncing)
                  IconButton(
                    tooltip: 'Отменить синхронизацию',
                    onPressed: s.cancelSync,
                    icon: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Синхронизировать',
                    onPressed: () {
                      if (!s.settings.syncConfigured &&
                          !s.settings.googleConfigured) {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => SettingsScreen(
                                store: s,
                                onTheme: widget.onTheme,
                                onLogout: widget.onLogout)));
                      } else {
                        s.syncAll();
                      }
                    },
                  ),
              ],
            ),
            drawer: _drawer(),
            body: Stack(children: [
              _body(),
              if (s.syncing)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(value: s.progress, minHeight: 2),
                ),
              if (_tab == 'home' && _on('notes')) Fab(onPressed: _quickCreate),
            ]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _mods.contains(_tab) ? _mods.indexOf(_tab) : 0,
              onDestinationSelected: (i) => _go(_mods[i]),
              destinations: [
                for (final m in _mods)
                  NavigationDestination(icon: Icon(_icons[m]), label: _names[m]!),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Окно-напоминание (Windows): висит, пока не закроют, со звуком.
class _AlertView extends StatelessWidget {
  final CalEvent event;
  const _AlertView({required this.event});

  @override
  Widget build(BuildContext context) {
    final when = event.allDay
        ? fmtDay(event.startDt)
        : '${fmtDay(event.startDt)}, ${fmtTime(event.startDt)}';
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(event.isTask ? Icons.check_circle_outline : Icons.notifications_active,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(event.isTask ? 'Задача' : 'Напоминание',
                  style: TextStyle(color: Pal.secondary(context))),
            ]),
            const SizedBox(height: 10),
            Text(event.title.isEmpty ? 'Без названия' : event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(when, style: TextStyle(color: Pal.secondary(context))),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Desktop.I.closeAlert(open: false),
                  child: const Text('Закрыть')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => Desktop.I.closeAlert(open: true),
                  child: const Text('Открыть')),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Главная, когда модуль «Заметки» отключён: быстрые переходы к включённым модулям.
class _ModulesHome extends StatelessWidget {
  final List<String> mods;
  final void Function(String) onOpen;
  const _ModulesHome({required this.mods, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const names = {
      'calendar': 'Календарь',
      'pass': 'Пароли',
      'chat': 'Чаты',
    };
    const icons = {
      'calendar': Icons.calendar_month_outlined,
      'pass': Icons.key_outlined,
      'chat': Icons.chat_bubble_outline,
    };
    final l = mods.where((m) => names.containsKey(m)).toList();
    if (l.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Все модули отключены. Включите нужные в Настройки → Модули.',
                  textAlign: TextAlign.center)));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final m in l)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: ListTile(
              leading: Icon(icons[m]),
              title: Text(names[m]!),
              onTap: () => onOpen(m),
            ),
          ),
        ),
    ]);
  }
}
