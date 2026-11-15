import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';

/// Google Диск через Drive API v3 (OAuth 2.0). Доступ только к файлам, которые создало
/// приложение (область drive.file): чужие файлы на диске приложению не видны.
class GDrive {
  static String? _token;
  static DateTime _exp = DateTime(2000);
  static const scope = 'https://www.googleapis.com/auth/drive.file';

  static Future<void> authorize(Store s) async {
    final st = s.settings;
    st.gdRefresh = await authorizeRaw(st.gClientId, st.gSecret);
    _token = null;
    await s.saveSettings();
  }

  /// Вход в Google; возвращает refresh-токен (без сохранения в настройки).
  static Future<String> authorizeRaw(String clientId, String secret) async {
    final st = Settings(gClientId: clientId, gSecret: secret);
    if (st.gClientId.isEmpty || st.gSecret.isEmpty) {
      throw 'Укажите Client ID и Client Secret Google';
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': st.gClientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': scope,
      'access_type': 'offline',
      'prompt': 'consent',
    });
    String? code;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      final req = await server.first.timeout(const Duration(minutes: 3));
      code = req.uri.queryParameters['code'];
      req.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
      req.response.write(
          '<html><body style="font-family:sans-serif"><h3>Готово. Окно можно закрыть и вернуться в приложение.</h3></body></html>');
      await req.response.close();
    } finally {
      await server.close(force: true);
    }
    if (code == null) throw 'Код авторизации не получен';
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'code': code,
      'client_id': st.gClientId,
      'client_secret': st.gSecret,
      'redirect_uri': redirect,
      'grant_type': 'authorization_code',
    });
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || j['refresh_token'] == null) {
      throw 'Google: ${j['error_description'] ?? j['error'] ?? r.statusCode}';
    }
    _token = null;
    return j['refresh_token'] as String;
  }

  static Future<String> access(Settings st) async {
    if (_token != null && DateTime.now().isBefore(_exp)) return _token!;
    if (st.gdRefresh.isEmpty) throw 'Google Диск: нет входа. Выполните вход в настройках';
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': st.gClientId,
      'client_secret': st.gSecret,
      'refresh_token': st.gdRefresh,
      'grant_type': 'refresh_token',
    });
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw 'Google: ${j['error_description'] ?? j['error'] ?? r.statusCode}';
    }
    _token = j['access_token'] as String;
    _exp = DateTime.now().add(Duration(seconds: ((j['expires_in'] ?? 3600) as num).toInt() - 60));
    return _token!;
  }

  static void forget() => _token = null;
}

/// Хранилище ASRbox на Google Диске. Пути «/папка/файл» превращаются в цепочку папок Drive.
class GDriveRemote extends Remote {
  final Settings st;
  final String base; // подпапка внутри «Мой диск», например /ASRbox-Backups
  final Map<String, String> _ids = {'/': 'root'};

  GDriveRemote(this.st, {this.base = ''});

  @override
  String get label => 'Google Диск';

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _up = 'https://www.googleapis.com/upload/drive/v3';

  String _norm(String path) {
    final p = '$base/$path'.replaceAll(RegExp(r'/+'), '/');
    return p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  }

  Future<http.Response> _send(String method, Uri url,
      {List<int>? body, Map<String, String>? headers}) async {
    Object? last;
    for (var i = 0; i < 3; i++) {
      final t0 = DateTime.now();
      try {
        final req = http.Request(method, url);
        req.headers['Authorization'] = 'Bearer ${await GDrive.access(st)}';
        if (headers != null) req.headers.addAll(headers);
        if (body != null) req.bodyBytes = body;
        final r = await http.Response.fromStream(
            await req.send().timeout(const Duration(seconds: 90)));
        Net.add(method, url.path, body?.length ?? 0, r.bodyBytes.length,
            DateTime.now().difference(t0).inMilliseconds, 'HTTP ${r.statusCode}');
        if (r.statusCode == 401) GDrive.forget();
        if ((r.statusCode >= 500 || r.statusCode == 429 || r.statusCode == 401) && i < 2) {
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
      await Future<void>.delayed(Duration(seconds: 1 << i));
    }
    throw 'Нет связи с Google Диском: $last';
  }

  Map<String, dynamic> _json(http.Response r) {
    if (r.statusCode >= 400) {
      String msg = '${r.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        msg = '${(j['error'] as Map?)?['message'] ?? r.statusCode}';
      } catch (_) {}
      throw 'Google Диск: $msg';
    }
    if (r.bodyBytes.isEmpty) return {};
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  String _q(String s) => s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  Future<List<Map<String, dynamic>>> _children(String parentId, {String? name}) async {
    final out = <Map<String, dynamic>>[];
    String? page;
    do {
      final q = "'$parentId' in parents and trashed=false"
          "${name != null ? " and name='${_q(name)}'" : ''}";
      final r = await _send(
          'GET',
          Uri.parse('$_api/files').replace(queryParameters: {
            'q': q,
            'fields': 'nextPageToken,files(id,name,mimeType)',
            'pageSize': '1000',
            if (page != null) 'pageToken': page,
          }));
      final j = _json(r);
      out.addAll(((j['files'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)));
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<String?> _idOf(String path) async {
    final p = _norm(path);
    if (_ids.containsKey(p)) return _ids[p];
    var cur = 'root';
    var acc = '';
    for (final seg in p.split('/').where((e) => e.isNotEmpty)) {
      acc = '$acc/$seg';
      final hit = _ids[acc];
      if (hit != null) {
        cur = hit;
        continue;
      }
      final l = await _children(cur, name: seg);
      if (l.isEmpty) return null;
      cur = l.first['id'] as String;
      _ids[acc] = cur;
    }
    return cur;
  }

  Future<String?> _parentOf(String path) async {
    final p = _norm(path);
    final i = p.lastIndexOf('/');
    return _idOf(i <= 0 ? '/' : p.substring(0, i));
  }

  String _nameOf(String path) => _norm(path).split('/').last;

  @override
  Future<void> mkcol(String path) async {
    final p = _norm(path);
    if (await _idOf(p) != null) return;
    final parent = await _parentOf(p);
    if (parent == null) return;
    final r = await _send('POST', Uri.parse('$_api/files?fields=id'),
        headers: {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({
          'name': _nameOf(p),
          'mimeType': 'application/vnd.google-apps.folder',
          'parents': [parent],
        })));
    _ids[p] = _json(r)['id'] as String;
  }

  @override
  Future<Uint8List?> get(String path) async {
    final id = await _idOf(path);
    if (id == null) return null;
    final r = await _send('GET', Uri.parse('$_api/files/$id?alt=media'));
    if (r.statusCode == 404) return null;
    if (r.statusCode >= 400) _json(r);
    return r.bodyBytes;
  }

  @override
  Future<void> put(String path, List<int> data) async {
    final p = _norm(path);
    final id = await _idOf(p);
    if (id != null) {
      final r = await _send('PATCH', Uri.parse('$_up/files/$id?uploadType=media'),
          headers: {'Content-Type': 'application/octet-stream'}, body: data);
      _json(r);
      return;
    }
    final parent = await _parentOf(p);
    if (parent == null) throw 'Google Диск: нет папки для $path';
    const b = 'asrbox_boundary_7d1e';
    final meta = utf8.encode(jsonEncode({'name': _nameOf(p), 'parents': [parent]}));
    final body = BytesBuilder()
      ..add(utf8.encode('--$b\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(meta)
      ..add(utf8.encode('\r\n--$b\r\nContent-Type: application/octet-stream\r\n\r\n'))
      ..add(data)
      ..add(utf8.encode('\r\n--$b--'));
    final r = await _send('POST', Uri.parse('$_up/files?uploadType=multipart&fields=id'),
        headers: {'Content-Type': 'multipart/related; boundary=$b'}, body: body.toBytes());
    _ids[p] = _json(r)['id'] as String;
  }

  @override
  Future<void> delete(String path) async {
    final id = await _idOf(path);
    if (id == null) return;
    try {
      await _send('DELETE', Uri.parse('$_api/files/$id'));
    } catch (_) {}
    _ids.remove(_norm(path));
  }

  Future<List<String>> _names(String path, bool dirs) async {
    final id = await _idOf(path);
    if (id == null) return [];
    const folder = 'application/vnd.google-apps.folder';
    return (await _children(id))
        .where((e) => (e['mimeType'] == folder) == dirs)
        .map((e) => e['name'] as String)
        .toList();
  }

  @override
  Future<List<String>> list(String path) => _names(path, false);

  @override
  Future<List<String>> listDirs(String path) => _names(path, true);

  /// Загрузка в Drive атомарна (файл появляется только после полной загрузки).
  @override
  Future<void> putAtomic(String path, List<int> data) => put(path, data);
}
