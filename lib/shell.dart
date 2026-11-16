// ▸ Оболочка: вкладки, боковое меню (телефон), левая панель (компьютер), модули
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'backup.dart';
import 'folder_sync.dart';
import 'sidebar.dart';
import 'schedule_panel.dart';
import 'app_menu.dart';
import 'backup_page.dart';
import 'bg_sync.dart';
import 'calendar_page.dart';
import 'desktop.dart';
import 'desktop_notes.dart';
import 'editor.dart';
import 'event_screen.dart';
import 'models.dart';
import 'notes_page.dart';
import 'phone_data.dart';
import 'pass_page.dart';
import 'pass_store.dart';
import 'settings_screen.dart';
import 'shared_page.dart';
import 'store.dart';
import 'remote.dart';
import 'diag_screens.dart';
import 'trash_screen.dart';
import 'util.dart';
import 'voice_page.dart';
import 'dock.dart';
import 'win_module.dart';
import 'widgets.dart';

part 'shell_2.dart';
part 'shell_3.dart';


/// Главная оболочка: нижняя навигация, боковое меню (профиль, модули,
/// «Избранное», настройки, тема), кнопка и строка статуса синхронизации сверху.
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
  String? _tag;
  String _folder = ''; // папка, открытая из «Избранного»
  int _folderSeq = 0;
  bool _navShown = true;
  Timer? _timer;
  Timer? _tick;
  Timer? _sched;
  final int _started = nowMs();
  StreamSubscription<List<ConnectivityResult>>? _conn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (s.settings.syncOnStart) s.syncAll(auto: true);
    s.warmSearch();
    WinService.apply(s); // переназначение клавиш и горячая клавиша диктовки (Windows)
    if (BgSync.available) BgSync.apply(s.settings.bgSync);
    Backup.autoIfDue(s);
    PhoneData.autoIfDue(s);
    _timer = Timer.periodic(const Duration(minutes: 30), (_) {
      Backup.autoIfDue(s);
      PhoneData.autoIfDue(s);
      FolderSync.autoIfDue(s);
    });
    // периодическая синхронизация по настройке «Синхронизация → Периодически»
    _sched = Timer.periodic(const Duration(minutes: 1), (_) {
      final m = s.settings.syncEvery;
      if (m <= 0 || s.syncing) return;
      final last = s.lastRunMs > _started ? s.lastRunMs : _started;
      if (nowMs() - last >= Duration(minutes: m).inMilliseconds) s.syncAll(auto: true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (s.syncing && mounted) setState(() {});
    });
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (s.settings.syncOnNet && !r.contains(ConnectivityResult.none)) s.syncAll(auto: true);
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
    _tick?.cancel();
    _sched?.cancel();
    _conn?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        s.settings.modLock.containsKey(_tab) &&
        !s.moduleLocked(_tab)) {
      s.moduleTouch(_tab);
    }
    if (state == AppLifecycleState.resumed && s.settings.syncOnResume) s.syncAll(auto: true);
  }

  static const _icons = {
    'home': Icons.home_outlined,
    'notes': Icons.notes,
    'shared': Icons.folder_shared_outlined,
    'calendar': Icons.calendar_month_outlined,
    'pass': Icons.key_outlined,
    'voice': Icons.mic_none,
    'windows': Icons.keyboard_outlined,
    'dock': Icons.dock,
    'backup': Icons.backup_outlined,
  };
  static const _names = {
    'home': 'Главная',
    'notes': 'Заметки',
    'shared': 'Общая папка',
    'calendar': 'Календарь',
    'pass': 'Пароли',
    'voice': 'Диктовка',
    'windows': 'Windows',
    'dock': 'Док',
    'backup': 'Бэкап',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CalEvent?>(
      valueListenable: Desktop.I.alert,
      builder: (context, alert, _) {
        if (alert != null) return _AlertView(event: alert);
        return AnimatedBuilder(
          animation: s,
          builder: (context, _) {
            final nav = _navMods;
            final desk = s.useDesktop(MediaQuery.of(context).size.width);
            if (desk && _tab == 'home' && _on('notes')) {
              _tab = 'notes';
              _visited.add('notes');
            }
            if (desk) {
              return Scaffold(
                body: Column(children: [
                  AppMenu(
                    s: s,
                    mods: _mods.where((m) => !(m == 'home' && _on('notes'))).toList(),
                    names: _names,
                    h: MenuHandlers(
                      go: _go,
                      newNote: _newNote,
                      newEvent: _newEvent,
                      newTask: () => _newEvent(task: true),
                      settings: _openSettings,
                      trash: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => TrashScreen(store: s))),
                      switchProfile: () => widget.onLogout(true),
                      toPhoneView: () {
                        s.settings.uiMode = 'mobile';
                        s.saveSettings();
                        s.refresh();
                      },
                      toggleTheme: () {
                        final dark = Theme.of(context).brightness == Brightness.dark;
                        s.settings.theme = dark ? 'light' : 'dark';
                        s.saveSettings();
                        widget.onTheme(s.settings.theme);
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(children: [
                      Sidebar(
                        s: s,
                        tab: _tab,
                        mods: _mods,
                        names: _names,
                        icons: _icons,
                        go: _go,
                        newNote: _newNote,
                        settings: _openSettings,
                        trash: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => TrashScreen(store: s))),
                        toggleTheme: () {
                          final dark = Theme.of(context).brightness == Brightness.dark;
                          s.settings.theme = dark ? 'light' : 'dark';
                          s.saveSettings();
                          widget.onTheme(s.settings.theme);
                        },
                        toPhoneView: () {
                          s.settings.uiMode = 'mobile';
                          s.saveSettings();
                          s.refresh();
                        },
                        openFolder: (id) {
                          setState(() {
                            _folder = id;
                            _folderSeq++;
                            _tag = null;
                          });
                          _go('notes');
                        },
                      ),
                      Expanded(child: _body()),
                      if (s.settings.showSchedule && MediaQuery.of(context).size.width >= 980) ...[
                        VerticalDivider(width: 1, color: Pal.border(context)),
                        SchedulePanel(store: s),
                      ],
                    ]),
                  ),
                ]),
              );
            }
            // Android: «назад» на главном экране сворачивает приложение, а не закрывает его
            return PopScope(
              canPop: !Platform.isAndroid,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) nativeChannel.invokeMethod<void>('minimize');
              },
              child: Scaffold(
              appBar: AppBar(
                title: Text(_title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
                actions: [
                  _syncButton(),
                  const SizedBox(width: 4),
                ],
              ),
              drawer: _drawer(),
              body: NotificationListener<UserScrollNotification>(
                onNotification: (n) {
                  if (s.settings.navMode == 'auto' && n.metrics.axis == Axis.vertical) {
                    final show = n.direction != ScrollDirection.reverse;
                    if (n.direction != ScrollDirection.idle && show != _navShown) {
                      setState(() => _navShown = show);
                    }
                  }
                  return false;
                },
                child: Stack(children: [
                  _body(),
                  if (_tab == 'home' && _on('notes')) Fab(onPressed: _quickCreate),
                ]),
              ),
              bottomNavigationBar: s.settings.navMode == 'hide'
                  ? null
                  : ClipRect(
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 180),
                        alignment: Alignment.topCenter,
                        heightFactor: (s.settings.navMode == 'auto' && !_navShown) ? 0.0 : 1.0,
                        child: NavigationBar(
                          selectedIndex: nav.contains(_tab) ? nav.indexOf(_tab) : 0,
                          onDestinationSelected: (i) => _go(nav[i]),
                          destinations: [
                            for (final m in nav)
                              NavigationDestination(icon: Icon(_icons[m]), label: _names[m]!),
                          ],
                        ),
                      ),
                    ),
            ));
          },
        );
      },
    );
  }}