import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_dirs.dart';
import 'applog.dart';
import 'autofill.dart';
import 'backup.dart';
import 'bg_sync.dart';
import 'calendars.dart';
import 'diag_screens.dart';
import 'gdrive.dart';
import 'import_formats.dart';
import 'google.dart';
import 'ics.dart';
import 'local_tx.dart';
import 'folder_sync.dart';
import 'model_dl.dart';
import 'models.dart';
import 'pdf_export.dart';
import 'store.dart';
import 'sync.dart';
import 'util.dart';
import 'widgets.dart';

part 'settings_screen_2.dart';
part 'settings_screen_3.dart';
part 'settings_screen_4.dart';
part 'settings_screen_5.dart';
part 'settings_screen_6.dart';
part 'settings_screen_7.dart';
part 'settings_screen_8.dart';
part 'settings_screen_9.dart';


const List<int> kProfileColors = [
  0xFF007AFF, 0xFFFF3B30, 0xFFFF9500, 0xFF34C759, 0xFF5856D6, 0xFFAF52DE, 0xFF00C7BE,
];

class SettingsScreen extends StatefulWidget {
  final Store store;
  final void Function(String theme) onTheme;
  final Future<void> Function(bool picker) onLogout;
  const SettingsScreen(
      {super.key,
      required this.store,
      required this.onTheme,
      required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Map<String, TextEditingController> c;
  late Settings st;
  bool bioAvail = false;
  String gStatus = '';
  Timer? _autoTimer;
  String _syncSig = '';

  @override
  void initState() {
    super.initState();
    st = s.settings;
    c = {
      'author': TextEditingController(text: st.author),
      'url': TextEditingController(text: st.url),
      'user': TextEditingController(text: st.user),
      'pass': TextEditingController(text: st.pass),
      'txUrl': TextEditingController(text: st.txUrl),
      'txKey': TextEditingController(text: st.txKey),
      'txModel': TextEditingController(text: st.txModel),
      'gId': TextEditingController(text: st.gClientId),
      'gSecret': TextEditingController(text: st.gSecret),
      'lock': TextEditingController(text: st.autoLock.toString()),
      'bkUrl': TextEditingController(text: st.bkUrl),
      'bkUser': TextEditingController(text: st.bkUser),
      'bkPass': TextEditingController(text: st.bkPass),
      'bkFolder': TextEditingController(text: st.bkFolder),
    };
    _syncSig = '${st.url}|${st.user}|${st.pass}';
    s.bioAvailable().then((v) {
      if (mounted) setState(() => bioAvail = v);
    });
  }

  @override
  void dispose() {
    // несохранённые правки записываем сразу
    if (_autoTimer?.isActive ?? false) {
      _autoTimer!.cancel();
      _autoNow();
    }
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  /// Папки настроек: каждая относится к модулю или общей теме.
  static const _folders = <(String, String, List<String>, bool)>[
    ('⚙️', 'Основные', ['Профиль', 'Модули', 'Блокировка разделов', 'Безопасность', 'Шифрование', 'Сохранение', 'Сброс'], false),
    ('☁️', 'Синхронизация и бэкап', ['Синхронизация WebDAV', 'Когда синхронизировать', 'История синхронизации', 'Резервная копия и перенос', 'Файлы и папки на сервер'], false),
    ('📝', 'Заметки', ['Фото'], false),
    ('📅', 'Календарь', ['Календари', 'Google Календарь'], false),
    ('👥', 'Общая папка', ['Общая папка'], false),
    ('🔑', 'Пароли', ['Пароли'], false),
    ('🎙', 'Голос', ['Голос'], false),
    ('🖥', 'Компьютер', ['Портативный режим'], true),
    ('🛠', 'Отладка', ['Отладка и диагностика'], false),
    // сюда добавляются модули только для компьютера (4-е поле true): на телефоне скрыты
  ];

  /// Папки, доступные на этой платформе.
  static List<(String, String, List<String>, bool)> get _visible =>
      [for (final f in _folders) if (!f.$4 || Platform.isWindows || Platform.isLinux || Platform.isMacOS) f];
  String? _folder;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 820;
    final secs = _sections();
    final sel = _folder == null ? (wide ? 0 : -1) : _visible.indexWhere((f) => f.$2 == _folder);
    final inFolder = !wide && sel >= 0;
    Widget body;
    if (wide) {
      body = Row(children: [
        Container(
          width: 240,
          decoration: BoxDecoration(
            color: Pal.sidebar(context),
            border: Border(right: BorderSide(color: Pal.border(context))),
          ),
          child: ListView(padding: const EdgeInsets.only(top: 12), children: [
            for (var i = 0; i < _visible.length; i++)
              _folderRow(i, i == sel, () => setState(() => _folder = _visible[i].$2), wide: true),
          ]),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720), child: _folderBody(sel, secs)),
          ),
        ),
      ]);
    } else if (inFolder) {
      body = _folderBody(sel, secs);
    } else {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        for (var i = 0; i < _visible.length; i++)
          _folderRow(i, false, () => setState(() => _folder = _visible[i].$2)),
      ]);
    }
    return PopScope(
      canPop: !inFolder,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _folder = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(inFolder ? _visible[sel].$2 : 'Настройки'),
          leading: inFolder
              ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _folder = null))
              : null,
          actions: [
            TextButton.icon(
                onPressed: _saveOnly, icon: const Icon(Icons.check), label: const Text('Сохранить')),
          ],
        ),
        body: body,
      ),
    );
  }}