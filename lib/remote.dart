import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Одна запись журнала передачи данных.
class NetEvent {
  final int at;
  final String op; // GET, PUT, … или «этап»
  final String target;
  final int up;
  final int down;
  final int ms;
  final String result;
  NetEvent(this.at, this.op, this.target, this.up, this.down, this.ms, this.result);
}

/// Счётчики и подробный журнал сетевых операций (для статус-бара и окна процессов).
class Net {
  static int up = 0;
  static int down = 0;
  static final List<NetEvent> log = [];
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static String _lastStage = '';

  static void add(String op, String target, int u, int d, int ms, String result) {
    up += u;
    down += d;
    log.add(NetEvent(DateTime.now().millisecondsSinceEpoch, op, target, u, d, ms, result));
    if (log.length > 1500) log.removeRange(0, log.length - 1200);
    tick.value++;
  }

  /// Этап синхронизации (текст статуса) — попадает в журнал один раз.
  static void stage(String text) {
    if (text.isEmpty || text == _lastStage) return;
    _lastStage = text;
    add('этап', text, 0, 0, 0, '');
  }

  /// Скорость (байт/с) за последние 4 секунды: отдача и загрузка.
  static (double, double) speed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var u = 0, d = 0;
    for (var i = log.length - 1; i >= 0; i--) {
      final e = log[i];
      if (now - e.at > 4000) break;
      u += e.up;
      d += e.down;
    }
    return (u / 4, d / 4);
  }

  static String fmtSpeed(double bps) {
    if (bps < 1024) return '${bps.round()} Б/с';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} КБ/с';
    return '${(bps / 1024 / 1024).toStringAsFixed(2)} МБ/с';
  }

  static String fmtSize(int b) {
    if (b < 1024) return '$b Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} МБ';
  }
}

/// Хранилище данных: WebDAV или обычная папка на устройстве.
/// Пути всегда вида «/папка/файл».
abstract class Remote {
  String get label;
  Future<void> mkcol(String path);

  /// Создать папку вместе со всеми родительскими.
  Future<void> mkcolAll(String path) async {
    var cur = '';
    for (final p in path.split('/').where((e) => e.isNotEmpty)) {
      cur = '$cur/$p';
      await mkcol(cur);
    }
  }

  Future<Uint8List?> get(String path);
  Future<void> put(String path, List<int> data);
  Future<void> delete(String path);

  /// Имена файлов в папке (без вложенных папок)
  Future<List<String>> list(String path);

  /// Имена вложенных папок
  Future<List<String>> listDirs(String path);

  /// Надёжная запись: сначала во временный файл, затем переименование.
  Future<void> putAtomic(String path, List<int> data);
}

class Dav extends Remote {
  final String base;
  final String auth;

  Dav(String url, String user, String pass)
      : base = url.replaceAll(RegExp(r'/+$'), ''),
        auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

  @override
  String get label => base;

  Uri _u(String p) => Uri.parse('$base$p');

  /// Запрос с повторами: сеть бывает нестабильной, 5xx и таймауты повторяем.
  Future<http.Response> _send(String method, String path,
      {List<int>? body, Map<String, String>? headers}) async {
    Object? last;
    for (var i = 0; i < 3; i++) {
      final t0 = DateTime.now();
      try {
        final req = http.Request(method, _u(path));
        req.headers['Authorization'] = auth;
        if (headers != null) req.headers.addAll(headers);
        if (body != null) req.bodyBytes = body;
        final s = await req.send().timeout(const Duration(seconds: 90));
        final r = await http.Response.fromStream(s);
        Net.add(method, path, body?.length ?? 0, r.bodyBytes.length,
            DateTime.now().difference(t0).inMilliseconds, 'HTTP ${r.statusCode}');
        if ((r.statusCode >= 500 || r.statusCode == 429) && i < 2) {
          last = 'HTTP ${r.statusCode}';
          await Future<void>.delayed(Duration(seconds: 1 << i));
          continue;
        }
        return r;
      } on TimeoutException catch (e) {
        last = e;
      } on SocketException catch (e) {
        last = e;
      } on http.ClientException catch (e) {
        last = e;
      }
      Net.add(method, path, 0, 0, DateTime.now().difference(t0).inMilliseconds, 'ошибка: $last');
      await Future<void>.delayed(Duration(seconds: 1 << i));
    }
    throw 'Нет связи с сервером: $last';
  }

  void _checkAuth(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw 'Доступ запрещён (${r.statusCode}): проверьте логин и пароль приложения';
    }
  }

  /// Создать папку; ошибки (в т.ч. «уже существует») игнорируются.
  @override
  Future<void> mkcol(String path) async {
    try {
      await _send('MKCOL', path);
    } catch (_) {}
  }

  @override
  Future<Uint8List?> get(String path) async {
    final r = await _send('GET', path);
    if (r.statusCode == 404) return null;
    _checkAuth(r);
    if (r.statusCode >= 400) throw 'GET $path: ${r.statusCode}';
    return r.bodyBytes;
  }

  @override
  Future<void> put(String path, List<int> data) async {
    final r = await _send('PUT', path, body: data);
    _checkAuth(r);
    if (r.statusCode >= 300) throw 'PUT $path: ${r.statusCode}';
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _send('DELETE', path);
    } catch (_) {}
  }

  Future<List<String>> _propfind(String path, {required bool dirs}) async {
    final r = await _send('PROPFIND', path, headers: {
      'Depth': '1',
      'Content-Type': 'application/xml',
    }, body: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>'));
    if (r.statusCode == 404) return [];
    _checkAuth(r);
    if (r.statusCode >= 400) throw 'PROPFIND $path: ${r.statusCode}';
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final re = RegExp(
        r'<(?:[A-Za-z0-9]+:)?href>\s*([^<]+?)\s*</(?:[A-Za-z0-9]+:)?href>',
        caseSensitive: false);
    final self = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final out = <String>[];
    var first = true;
    for (final m in re.allMatches(body)) {
      var h = m.group(1)!;
      if (h.startsWith('http')) h = Uri.parse(h).path;
      h = Uri.decodeFull(h);
      final isDir = h.endsWith('/');
      final trimmed = h.replaceAll(RegExp(r'^/+|/+$'), '');
      if (first && isDir && (trimmed == self || trimmed.endsWith('/$self') || self.isEmpty)) {
        first = false; // сама запрошенная папка
        continue;
      }
      first = false;
      if (isDir != dirs) continue;
      final name = trimmed.split('/').last;
      if (name.isNotEmpty) out.add(name);
    }
    return out;
  }

  @override
  Future<List<String>> list(String path) => _propfind(path, dirs: false);

  @override
  Future<List<String>> listDirs(String path) => _propfind(path, dirs: true);

  @override
  Future<void> putAtomic(String path, List<int> data) async {
    final tmp = '$path.tmp';
    await put(tmp, data);
    final r = await _send('MOVE', tmp, headers: {
      'Destination': _u(path).toString(),
      'Overwrite': 'T',
    });
    if (r.statusCode >= 300) {
      await put(path, data);
      await delete(tmp);
    }
  }
}

/// Обычная папка на устройстве (внешний диск, папка, которую синхронизирует другая программа).
class LocalRemote extends Remote {
  final String base;
  LocalRemote(String dir) : base = dir.replaceAll(RegExp(r'[\\/]+$'), '');

  @override
  String get label => base;

  String _p(String path) {
    if (path.contains('..')) throw 'Недопустимый путь';
    final p = path.replaceAll('/', Platform.pathSeparator);
    return '$base${p.startsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$p';
  }

  @override
  Future<void> mkcol(String path) async {
    try {
      await Directory(_p(path)).create(recursive: true);
    } catch (_) {}
  }

  @override
  Future<Uint8List?> get(String path) async {
    final f = File(_p(path));
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> put(String path, List<int> data) async {
    final f = File(_p(path));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    try {
      final f = File(_p(path));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<List<String>> list(String path) async {
    final d = Directory(_p(path));
    if (!await d.exists()) return [];
    final out = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is File) {
        final n = e.uri.pathSegments.last;
        if (!n.endsWith('.tmp')) out.add(n);
      }
    }
    return out;
  }

  @override
  Future<List<String>> listDirs(String path) async {
    final d = Directory(_p(path));
    if (!await d.exists()) return [];
    final out = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is Directory) {
        final segs = e.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) out.add(segs.last);
      }
    }
    return out;
  }

  @override
  Future<void> putAtomic(String path, List<int> data) async {
    final f = File(_p(path));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(f.path);
  }
}
