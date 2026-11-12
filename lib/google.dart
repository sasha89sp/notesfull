import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'store.dart';

/// Google Calendar через HTTPS (без Google Play Services).
/// Авторизация: OAuth «Desktop app» с обратным адресом на 127.0.0.1.
class GoogleCal {
  static String? _token;
  static DateTime _tokenExp = DateTime(2000);

  static Future<void> authorize(Store s) async {
    final st = s.settings;
    if (st.gClientId.isEmpty || st.gSecret.isEmpty) {
      throw 'Укажите Client ID и Client Secret';
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': st.gClientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': 'https://www.googleapis.com/auth/calendar',
      'access_type': 'offline',
      'prompt': 'consent',
    });
    String? code;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      final req = await server.first.timeout(const Duration(minutes: 3));
      code = req.uri.queryParameters['code'];
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(
          '<html><body style="font-family:sans-serif"><h3>Готово. Окно можно закрыть и вернуться в приложение.</h3></body></html>');
      await req.response.close();
    } finally {
      await server.close(force: true);
    }
    if (code == null) throw 'Код авторизации не получен';
    final r = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'code': code,
        'client_id': st.gClientId,
        'client_secret': st.gSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      },
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || j['refresh_token'] == null) {
      throw 'Google: ${j['error_description'] ?? j['error'] ?? r.statusCode}';
    }
    st.gRefresh = j['refresh_token'] as String;
    await s.saveSettings();
  }

  static Future<String> _access(Store s) async {
    if (_token != null && DateTime.now().isBefore(_tokenExp)) return _token!;
    final st = s.settings;
    final r = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': st.gClientId,
        'client_secret': st.gSecret,
        'refresh_token': st.gRefresh,
        'grant_type': 'refresh_token',
      },
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw 'Google: ${j['error_description'] ?? j['error'] ?? r.statusCode}';
    }
    _token = j['access_token'] as String;
    _tokenExp =
        DateTime.now().add(Duration(seconds: ((j['expires_in'] ?? 3000) as num).toInt() - 60));
    return _token!;
  }

  static Map<String, dynamic> _body(CalEvent e) {
    Map<String, dynamic> st, en;
    if (e.allDay) {
      final s = e.startDt;
      var d = e.endDt;
      if (!d.isAfter(s)) d = s.add(const Duration(days: 1));
      String ymd(DateTime x) => '${x.year}-${two(x.month)}-${two(x.day)}';
      st = {'date': ymd(s)};
      en = {'date': ymd(d)};
    } else {
      st = {'dateTime': e.startDt.toUtc().toIso8601String()};
      en = {'dateTime': e.endDt.toUtc().toIso8601String()};
    }
    return {
      'summary': e.title,
      'description': e.notes,
      'start': st,
      'end': en,
      'reminders': e.remind < 0
          ? {'useDefault': false}
          : {
              'useDefault': false,
              'overrides': [
                {'method': 'popup', 'minutes': e.remind}
              ]
            },
    };
  }

  static DateTime _parseG(Map<String, dynamic> m) {
    if (m['dateTime'] != null) {
      return DateTime.parse(m['dateTime'] as String).toLocal();
    }
    final p = (m['date'] as String).split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static Future<String> sync(Store s) async {
    final tok = await _access(s);
    final h = {
      'Authorization': 'Bearer $tok',
      'Content-Type': 'application/json',
    };
    var down = 0, up = 0;

    // 1. читаем изменения с сервера
    final min = DateTime.now()
        .subtract(const Duration(days: 60))
        .toUtc()
        .toIso8601String();
    final items = <Map<String, dynamic>>[];
    String? page;
    do {
      final uri = Uri.https(
          'www.googleapis.com', '/calendar/v3/calendars/primary/events', {
        'timeMin': min,
        'singleEvents': 'true',
        'showDeleted': 'true',
        'maxResults': '250',
        if (page != null) 'pageToken': page,
      });
      final r = await http.get(uri, headers: h);
      if (r.statusCode != 200) throw 'список событий: ${r.statusCode}';
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      for (final it in (j['items'] ?? []) as List) {
        items.add(Map<String, dynamic>.from(it as Map));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);

    for (final it in items) {
      final gid = it['id'] as String;
      CalEvent? local;
      for (final e in s.events) {
        if (e.gId == gid) local = e;
      }
      if (it['status'] == 'cancelled') {
        if (local != null && !local.deleted) {
          local.deleted = true;
          local.gId = '';
          local.updatedAt = nowMs();
          down++;
        }
        continue;
      }
      if (it['start'] == null || it['end'] == null) continue;
      final updated =
          DateTime.parse(it['updated'] as String).millisecondsSinceEpoch;
      final allDay = (it['start'] as Map)['date'] != null;
      final start = _parseG(Map<String, dynamic>.from(it['start'] as Map));
      var end = _parseG(Map<String, dynamic>.from(it['end'] as Map));
      if (allDay) end = end.subtract(const Duration(days: 1));
      int remind = -1;
      final rem = it['reminders'];
      if (rem is Map && rem['overrides'] is List && (rem['overrides'] as List).isNotEmpty) {
        remind = ((rem['overrides'] as List).first['minutes'] as num).toInt();
      }

      if (local == null) {
        s.events.add(CalEvent(
          id: newId(),
          title: (it['summary'] ?? '') as String,
          notes: (it['description'] ?? '') as String,
          start: start.millisecondsSinceEpoch,
          end: end.millisecondsSinceEpoch,
          allDay: allDay,
          remind: remind,
          gId: gid,
          gSynced: updated,
          gLocal: nowMs(),
          updatedAt: nowMs(),
        ));
        down++;
      } else if (updated > local.gSynced && local.updatedAt <= local.gLocal) {
        local.title = (it['summary'] ?? '') as String;
        local.notes = (it['description'] ?? '') as String;
        local.start = start.millisecondsSinceEpoch;
        local.end = end.millisecondsSinceEpoch;
        local.allDay = allDay;
        local.remind = remind;
        local.gSynced = updated;
        local.updatedAt = nowMs();
        local.gLocal = local.updatedAt;
        down++;
      }
    }

    // 2. отправляем локальные изменения (задачи остаются только локально)
    for (final e in List<CalEvent>.of(s.events)) {
      if (e.isTask) continue;
      if (e.deleted) {
        if (e.gId.isNotEmpty) {
          await http.delete(
              Uri.https('www.googleapis.com',
                  '/calendar/v3/calendars/primary/events/${e.gId}'),
              headers: h);
          e.gId = '';
          up++;
        }
        continue;
      }
      if (e.gId.isEmpty) {
        final r = await http.post(
            Uri.https(
                'www.googleapis.com', '/calendar/v3/calendars/primary/events'),
            headers: h,
            body: jsonEncode(_body(e)));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          e.gId = j['id'] as String;
          e.gSynced =
              DateTime.parse(j['updated'] as String).millisecondsSinceEpoch;
          e.gLocal = e.updatedAt;
          up++;
        }
      } else if (e.updatedAt > e.gLocal) {
        final r = await http.put(
            Uri.https('www.googleapis.com',
                '/calendar/v3/calendars/primary/events/${e.gId}'),
            headers: h,
            body: jsonEncode(_body(e)));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          e.gSynced =
              DateTime.parse(j['updated'] as String).millisecondsSinceEpoch;
          e.gLocal = e.updatedAt;
          up++;
        }
      }
    }
    return '↑$up ↓$down';
  }
}
