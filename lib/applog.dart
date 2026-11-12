import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogEntry {
  final DateTime at;
  final String level; // I | W | E | V
  final String module;
  final String msg;
  LogEntry(this.at, this.level, this.module, this.msg);

  String get line =>
      '${at.toIso8601String()}|$level|$module|${msg.replaceAll('\n', ' ⏎ ')}';

  static LogEntry? parse(String l) {
    final p = l.split('|');
    if (p.length < 4) return null;
    final t = DateTime.tryParse(p[0]);
    if (t == null) return null;
    return LogEntry(t, p[1], p[2], p.sublist(3).join('|').replaceAll(' ⏎ ', '\n'));
  }
}

/// Встроенный журнал: ошибки, сбои, зависания интерфейса и причины.
/// В журнал не пишутся пароли и содержимое заметок.
class AppLog extends ChangeNotifier {
  static final AppLog I = AppLog._();
  AppLog._();

  static const int _maxEntries = 800;
  static const int _maxFileBytes = 400 * 1024;

  final List<LogEntry> entries = [];
  bool verbose = false;
  File? _file;
  Timer? _wd;
  DateTime _wdLast = DateTime.now();

  Future<void> init() async {
    try {
      final d = await getApplicationSupportDirectory();
      if (!await d.exists()) await d.create(recursive: true);
      _file = File('${d.path}${Platform.pathSeparator}applog.txt');
      if (await _file!.exists()) {
        final lines = await _file!.readAsLines();
        for (final l in lines.skip(lines.length > _maxEntries ? lines.length - _maxEntries : 0)) {
          final e = LogEntry.parse(l);
          if (e != null) entries.add(e);
        }
      }
    } catch (_) {}
    i('app', 'Запуск приложения');
    _startWatchdog();
  }

  /// Сторож: если главный поток не отвечал больше 2 секунд, пишем «зависание».
  void _startWatchdog() {
    _wd?.cancel();
    _wdLast = DateTime.now();
    _wd = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final lag = now.difference(_wdLast).inMilliseconds - 1000;
      _wdLast = now;
      if (lag > 2000) {
        w('ui', 'Интерфейс не отвечал около ${(lag / 1000).toStringAsFixed(1)} с');
      }
    });
  }

  void _add(String level, String module, String msg) {
    final e = LogEntry(DateTime.now(), level, module, msg);
    entries.add(e);
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    if (kDebugMode) debugPrint(e.line);
    _append(e.line);
    notifyListeners();
  }

  Future<void> _append(String line) async {
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString('$line\n', mode: FileMode.append, flush: false);
      if (await f.length() > _maxFileBytes) {
        final lines = await f.readAsLines();
        final keep = lines.sublist(lines.length ~/ 2);
        await f.writeAsString('${keep.join('\n')}\n');
      }
    } catch (_) {}
  }

  void i(String module, String msg) => _add('I', module, msg);
  void w(String module, String msg) => _add('W', module, msg);
  void e(String module, String msg, [Object? stack]) {
    final st = stack == null ? '' : '\n${stack.toString().split('\n').take(6).join('\n')}';
    _add('E', module, '$msg$st');
  }

  /// Подробные сообщения: только если включено подробное логирование.
  void v(String module, String msg) {
    if (verbose) _add('V', module, msg);
  }

  String exportText() {
    final b = StringBuffer('Журнал приложения «Заметки»\n');
    for (final e in entries) {
      b.writeln('${e.at.toIso8601String()} [${e.level}] ${e.module}: ${e.msg}');
    }
    return b.toString();
  }

  Future<void> clear() async {
    entries.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
    notifyListeners();
  }
}
