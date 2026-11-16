// ▸ Синхронизация с Google Календарём
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'calendars.dart';
import 'models.dart';
import 'store.dart';
import 'synchist.dart';
part 'google_2.dart';


/// Google Calendar через HTTPS (без Google Play Services).
/// Авторизация: OAuth «Desktop app» с обратным адресом на 127.0.0.1.
class GoogleCal {
  /// В Google уходят только события «Основного» календаря и календаря Google; локальные и подписки — нет.
  static bool _toGoogle(CalEvent e) {
    final id = Cals.idOf(e);
    return id == 'main' || id == 'google';
  }

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

  static String _key(String title, int start, int end) =>
      '${title.trim().toLowerCase()}|$start|$end';

  /// Отключение аккаунта Google (локальные события остаются).
  static Future<void> disconnect(Store s) async {
    final st = s.settings;
    try {
      if (st.gRefresh.isNotEmpty) {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'),
            body: {'token': st.gRefresh});
      }
    } catch (_) {}
    st.gRefresh = '';
    _token = null;
    for (final e in s.events) {
      e.gId = '';
      e.gSynced = 0;
      e.gLocal = 0;
    }
    await s.saveSettings();
    await s.saveEvents();
    s.refresh();
  }}