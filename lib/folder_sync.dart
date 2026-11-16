// ▸ Правило «папка или файл → сервер»: односторонняя выгрузка (зеркало без удаления).
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'applog.dart';
import 'backup.dart';
import 'models.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Правило «папка или файл → сервер»: односторонняя выгрузка (зеркало без удаления).
class FolderSync {
  String id, name, path;
  bool isDir;
  int everyMin; // 0 — только вручную
  int last;
  String lastResult;
  FolderSync({
    required this.id,
    required this.name,
    required this.path,
    required this.isDir,
    this.everyMin = 0,
    this.last = 0,
    this.lastResult = '',
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'path': path, 'dir': isDir, 'every': everyMin, 'last': last, 'res': lastResult};

  factory FolderSync.fromJson(Map<String, dynamic> j) => FolderSync(
        id: (j['id'] ?? newId()) as String,
        name: (j['name'] ?? '') as String,
        path: (j['path'] ?? '') as String,
        isDir: (j['dir'] ?? true) as bool,
        everyMin: (j['every'] ?? 0) as int,
        last: (j['last'] ?? 0) as int,
        lastResult: (j['res'] ?? '') as String,
      );

  static const maxFile = 300 * 1024 * 1024;
  static final Set<String> _running = {};

  static List<FolderSync> all(Settings st) => [
        for (final m in st.folderSyncs) FolderSync.fromJson(Map<String, dynamic>.from(m)),
      ];

  static void save(Settings st, List<FolderSync> l) => st.folderSyncs = [for (final f in l) f.toJson()];

  /// Файл состояния: путь -> «размер:время изменения» уже выгруженных файлов.
  static File _stateFile(Store s) => File('${s.baseDir.path}${Platform.pathSeparator}foldersync_state.json');

  static Map<String, String> _loadState(Store s) {
    try {
      return Map<String, String>.from(jsonDecode(_stateFile(s).readAsStringSync()) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Выгружает изменённые файлы. Возвращает «выгружено N, пропущено M».
  static Future<String> run(Store s, FolderSync f) async {
    if (!Backup.canUpload(s.settings)) throw 'Не настроен сервер (Синхронизация и бэкап)';
    if (!_running.add(f.id)) return 'Уже выполняется';
    try {
      final (r, base) = Backup.target(s);
      final dest = '$base/files/${f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
      final state = _loadState(s);
      final files = <File>[];
      final root = f.path.replaceAll(RegExp(r'[\\/]+$'), '');
      if (f.isDir) {
        final d = Directory(f.path);
        if (!d.existsSync()) throw 'Папка не найдена: ${f.path}';
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is File) files.add(e);
        }
      } else {
        final x = File(f.path);
        if (!x.existsSync()) throw 'Файл не найден: ${f.path}';
        files.add(x);
      }
      await r.mkcolAll(dest);
      var up = 0, skip = 0, big = 0;
      final made = <String>{};
      for (final x in files) {
        final st = x.statSync();
        final sig = '${st.size}:${st.modified.millisecondsSinceEpoch}';
        final key = '${f.id}|${x.path}';
        if (state[key] == sig) {
          skip++;
          continue;
        }
        if (st.size > maxFile) {
          big++;
          continue;
        }
        var rel = f.isDir ? x.path.substring(root.length).replaceAll('\\', '/') : '/${x.path.split(RegExp(r'[\\/]')).last}';
        if (!rel.startsWith('/')) rel = '/$rel';
        final dir = rel.substring(0, rel.lastIndexOf('/'));
        if (dir.isNotEmpty && made.add(dir)) await r.mkcolAll('$dest$dir');
        await r.put('$dest$rel', await x.readAsBytes());
        state[key] = sig;
        up++;
      }
      try {
        _stateFile(s).writeAsStringSync(jsonEncode(state));
      } catch (_) {}
      final res = 'выгружено $up, без изменений $skip${big > 0 ? ', слишком большие (>300 МБ): $big' : ''}';
      AppLog.I.i('foldersync', '«${f.name}»: $res');
      return res;
    } finally {
      _running.remove(f.id);
    }
  }

  /// Автозапуск по расписанию (вызывается таймером оболочки).
  static Future<void> autoIfDue(Store s) async {
    if (s.key == null || !Backup.canUpload(s.settings)) return;
    final l = all(s.settings);
    var changed = false;
    for (final f in l) {
      if (f.everyMin <= 0 || nowMs() - f.last < f.everyMin * 60000) continue;
      try {
        f.lastResult = await run(s, f);
      } catch (e) {
        f.lastResult = 'ошибка: $e';
        AppLog.I.e('foldersync', '«${f.name}»: $e');
      }
      f.last = nowMs();
      changed = true;
    }
    if (changed) {
      save(s.settings, l);
      await s.saveSettings(touch: false);
    }
  }
}

/// Блок настроек: список правил, добавление, запуск, расписание.
class FolderSyncBox extends StatefulWidget {
  final Store s;
  const FolderSyncBox({super.key, required this.s});
  @override
  State<FolderSyncBox> createState() => _FolderSyncBoxState();
}

class _FolderSyncBoxState extends State<FolderSyncBox> {
  final Set<String> _busy = {};

  Store get s => widget.s;

  Future<void> _add(bool dir) async {
    String? path;
    if (dir) {
      path = await FilePicker.platform.getDirectoryPath();
    } else {
      final r = await FilePicker.platform.pickFiles();
      path = r?.files.single.path;
    }
    if (path == null) return;
    final l = FolderSync.all(s.settings);
    final nm = path.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last;
    l.add(FolderSync(id: newId(), name: nm, path: path, isDir: dir));
    FolderSync.save(s.settings, l);
    await s.saveSettings(touch: false);
    if (mounted) setState(() {});
  }

  Future<void> _run(FolderSync f) async {
    setState(() => _busy.add(f.id));
    String res;
    try {
      res = await FolderSync.run(s, f);
    } catch (e) {
      res = 'ошибка: $e';
    }
    final l = FolderSync.all(s.settings);
    for (final x in l) {
      if (x.id == f.id) {
        x.last = nowMs();
        x.lastResult = res;
      }
    }
    FolderSync.save(s.settings, l);
    await s.saveSettings(touch: false);
    if (mounted) setState(() => _busy.remove(f.id));
  }

  Future<void> _set(FolderSync f, {int? every, bool remove = false}) async {
    final l = FolderSync.all(s.settings);
    if (remove) {
      l.removeWhere((x) => x.id == f.id);
    } else {
      for (final x in l) {
        if (x.id == f.id && every != null) x.everyMin = every;
      }
    }
    FolderSync.save(s.settings, l);
    await s.saveSettings(touch: false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = FolderSync.all(s.settings);
    final sec = Pal.secondary(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Hint('Выбранные папки и файлы выгружаются на сервер бэкапов (в папку «files»). Выгружаются только '
          'изменённые файлы; удалённые у вас файлы на сервере остаются. Файлы хранятся без шифрования. '
          'Работает на всех платформах; на Android доступ к папке даёт системный выбор.'),
      for (final f in l)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(f.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                  tooltip: 'Убрать',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _set(f, remove: true)),
            ]),
            Text(f.path, style: TextStyle(fontSize: 11, color: sec), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (f.lastResult.isNotEmpty)
              Text('${f.last == 0 ? '' : '${fmtDay(DateTime.fromMillisecondsSinceEpoch(f.last))} · '}${f.lastResult}',
                  style: TextStyle(fontSize: 11, color: sec)),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _busy.contains(f.id) ? null : () => _run(f),
                icon: _busy.contains(f.id)
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Выгрузить'),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: const [0, 15, 60, 360, 1440].contains(f.everyMin) ? f.everyMin : 0,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Вручную')),
                  DropdownMenuItem(value: 15, child: Text('Каждые 15 мин')),
                  DropdownMenuItem(value: 60, child: Text('Каждый час')),
                  DropdownMenuItem(value: 360, child: Text('Каждые 6 часов')),
                  DropdownMenuItem(value: 1440, child: Text('Раз в сутки')),
                ],
                onChanged: (v) => _set(f, every: v),
              ),
            ]),
          ]),
        ),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
            onPressed: () => _add(true), icon: const Icon(Icons.create_new_folder_outlined, size: 18), label: const Text('Добавить папку')),
        OutlinedButton.icon(
            onPressed: () => _add(false), icon: const Icon(Icons.note_add_outlined, size: 18), label: const Text('Добавить файл')),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}
