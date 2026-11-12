import 'dart:convert';
import 'models.dart';
import 'util.dart';

/// Импорт и экспорт паролей: Bitwarden (JSON/CSV), KeePass (XML), LastPass (CSV),
/// 1Password (.1pif/.csv), Chrome/Firefox/Safari (CSV), универсальный CSV.
class PassIO {
  // ----------------------------------------------------------- импорт

  static List<PassEntry> import(String fileName, String text) {
    final low = fileName.toLowerCase();
    if (low.endsWith('.kdbx')) {
      throw 'Файлы .kdbx зашифрованы. В KeePass выберите «Файл → Экспорт → KeePass XML» и импортируйте .xml';
    }
    if (low.endsWith('.json')) return _bitwardenJson(text);
    if (low.endsWith('.xml')) return _keepassXml(text);
    if (low.endsWith('.1pif')) return _onePif(text);
    final t = text.trimLeft();
    if (t.startsWith('{')) return _bitwardenJson(text);
    if (t.startsWith('<?xml') || t.startsWith('<KeePassFile')) {
      return _keepassXml(text);
    }
    return _csv(text);
  }

  static List<PassEntry> _bitwardenJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['encrypted'] == true) {
      throw 'Файл Bitwarden зашифрован. Экспортируйте в «.json (незашифрованный)»';
    }
    final folders = <String, String>{};
    for (final f in (j['folders'] ?? []) as List) {
      final m = Map<String, dynamic>.from(f as Map);
      folders[(m['id'] ?? '').toString()] = (m['name'] ?? '').toString();
    }
    final out = <PassEntry>[];
    for (final it in (j['items'] ?? []) as List) {
      final m = Map<String, dynamic>.from(it as Map);
      final login = m['login'] is Map
          ? Map<String, dynamic>.from(m['login'] as Map)
          : <String, dynamic>{};
      var url = '';
      if (login['uris'] is List && (login['uris'] as List).isNotEmpty) {
        url = ((login['uris'] as List).first as Map)['uri']?.toString() ?? '';
      }
      final e = PassEntry.create()
        ..title = (m['name'] ?? '').toString()
        ..username = (login['username'] ?? '').toString()
        ..password = (login['password'] ?? '').toString()
        ..totp = (login['totp'] ?? '').toString()
        ..url = url
        ..notes = (m['notes'] ?? '').toString()
        ..favorite = m['favorite'] == true
        ..folder = folders[(m['folderId'] ?? '').toString()] ?? '';
      if (e.title.isNotEmpty || e.password.isNotEmpty) out.add(e);
    }
    return out;
  }

  static List<PassEntry> _csv(String text) {
    final rows = parseCsv(text);
    if (rows.length < 2) throw 'Пустой CSV-файл';
    final head = rows.first.map((e) => e.trim().toLowerCase()).toList();
    int idx(List<String> names) {
      for (final n in names) {
        final i = head.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final iTitle = idx(['name', 'title', 'login_name']);
    final iUser = idx(['login_username', 'username', 'login', 'user', 'login_user']);
    final iPass = idx(['login_password', 'password', 'pass']);
    final iUrl = idx(['login_uri', 'url', 'website', 'web site', 'login_url']);
    final iNotes = idx(['notes', 'note', 'extra', 'comments']);
    final iFolder = idx(['folder', 'grouping', 'group']);
    final iTotp = idx(['login_totp', 'totp', 'otpauth']);
    final iFav = idx(['favorite', 'fav']);
    if (iPass < 0) throw 'В CSV не найден столбец с паролем';

    String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';

    final out = <PassEntry>[];
    for (final r in rows.skip(1)) {
      final e = PassEntry.create()
        ..title = cell(r, iTitle)
        ..username = cell(r, iUser)
        ..password = cell(r, iPass)
        ..url = cell(r, iUrl)
        ..notes = cell(r, iNotes)
        ..folder = cell(r, iFolder)
        ..totp = cell(r, iTotp)
        ..favorite = cell(r, iFav) == '1' || cell(r, iFav).toLowerCase() == 'true';
      if (e.title.isEmpty) e.title = e.url;
      if (e.title.isNotEmpty || e.password.isNotEmpty) out.add(e);
    }
    return out;
  }

  static List<PassEntry> _keepassXml(String text) {
    final out = <PassEntry>[];
    final groups = <String>[];
    final re = RegExp(r'<Group>|</Group>|<Entry>.*?</Entry>', dotAll: true);
    for (final m in re.allMatches(text)) {
      final tok = m.group(0)!;
      if (tok == '<Group>') {
        final nm = RegExp(r'<Name>(.*?)</Name>', dotAll: true)
            .matchAsPrefix(text, m.end + _skipWs(text, m.end));
        groups.add(nm == null ? '' : unescapeXml(nm.group(1)!));
      } else if (tok == '</Group>') {
        if (groups.isNotEmpty) groups.removeLast();
      } else {
        final f = <String, String>{};
        for (final s in RegExp(
                r'<String>\s*<Key>(.*?)</Key>\s*<Value[^>]*>(.*?)</Value>',
                dotAll: true)
            .allMatches(tok)) {
          f[unescapeXml(s.group(1)!)] = unescapeXml(s.group(2)!);
        }
        if (tok.contains('<History>')) continue;
        final folder = groups.length > 1 ? groups.sublist(1).join('/') : '';
        final e = PassEntry.create()
          ..title = f['Title'] ?? ''
          ..username = f['UserName'] ?? ''
          ..password = f['Password'] ?? ''
          ..url = f['URL'] ?? ''
          ..notes = f['Notes'] ?? ''
          ..totp = f['otp'] ?? f['TOTP Seed'] ?? ''
          ..folder = folder;
        if (e.title.isNotEmpty || e.password.isNotEmpty) out.add(e);
      }
    }
    return out;
  }

  static int _skipWs(String s, int i) {
    var k = 0;
    while (i + k < s.length && s[i + k].trim().isEmpty) {
      k++;
    }
    return k;
  }

  static List<PassEntry> _onePif(String text) {
    final out = <PassEntry>[];
    for (final part in text.split(RegExp(r'\*{3}[0-9a-f-]{36}\*{3}'))) {
      final p = part.trim();
      if (!p.startsWith('{')) continue;
      try {
        final m = Map<String, dynamic>.from(jsonDecode(p) as Map);
        final sc = m['secureContents'] is Map
            ? Map<String, dynamic>.from(m['secureContents'] as Map)
            : <String, dynamic>{};
        final e = PassEntry.create()
          ..title = (m['title'] ?? '').toString()
          ..url = (m['location'] ?? '').toString()
          ..notes = (sc['notesPlain'] ?? '').toString();
        for (final f in (sc['fields'] ?? []) as List) {
          final fm = Map<String, dynamic>.from(f as Map);
          if (fm['designation'] == 'username') e.username = (fm['value'] ?? '').toString();
          if (fm['designation'] == 'password') e.password = (fm['value'] ?? '').toString();
        }
        if (e.password.isNotEmpty || e.title.isNotEmpty) out.add(e);
      } catch (_) {}
    }
    return out;
  }

  // ----------------------------------------------------------- экспорт

  static String exportCsv(List<PassEntry> list) {
    final rows = <List<String>>[
      ['name', 'url', 'username', 'password', 'notes', 'folder', 'totp', 'favorite'],
      for (final e in list)
        [
          e.title, e.url, e.username, e.password, e.notes, e.folder, e.totp,
          e.favorite ? '1' : '0'
        ],
    ];
    return toCsv(rows);
  }

  /// Bitwarden CSV (login_*)
  static String exportBitwardenCsv(List<PassEntry> list) {
    final rows = <List<String>>[
      ['folder', 'favorite', 'type', 'name', 'notes', 'fields', 'reprompt',
        'login_uri', 'login_username', 'login_password', 'login_totp'],
      for (final e in list)
        [
          e.folder, e.favorite ? '1' : '', 'login', e.title, e.notes, '', '0',
          e.url, e.username, e.password, e.totp
        ],
    ];
    return toCsv(rows);
  }

  static String exportBitwardenJson(List<PassEntry> list) {
    final folders = <String, String>{};
    for (final e in list) {
      if (e.folder.isNotEmpty) folders.putIfAbsent(e.folder, () => newId());
    }
    final j = {
      'encrypted': false,
      'folders': [
        for (final f in folders.entries) {'id': f.value, 'name': f.key}
      ],
      'items': [
        for (final e in list)
          {
            'id': e.id,
            'folderId': e.folder.isEmpty ? null : folders[e.folder],
            'type': 1,
            'name': e.title,
            'notes': e.notes.isEmpty ? null : e.notes,
            'favorite': e.favorite,
            'login': {
              'username': e.username,
              'password': e.password,
              'totp': e.totp.isEmpty ? null : e.totp,
              'uris': e.url.isEmpty
                  ? []
                  : [
                      {'match': null, 'uri': e.url}
                    ],
            },
          }
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(j);
  }

  static String exportKeepassXml(List<PassEntry> list) {
    final sb = StringBuffer();
    String field(String k, String v, {bool protect = false}) =>
        '<String><Key>$k</Key><Value${protect ? ' ProtectInMemory="True"' : ''}>${escapeXml(v)}</Value></String>';
    sb.write('<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n<KeePassFile><Root><Group><Name>Database</Name>');
    final byFolder = <String, List<PassEntry>>{};
    for (final e in list) {
      byFolder.putIfAbsent(e.folder, () => []).add(e);
    }
    void entries(List<PassEntry> l) {
      for (final e in l) {
        sb.write('<Entry>');
        sb.write(field('Title', e.title));
        sb.write(field('UserName', e.username));
        sb.write(field('Password', e.password, protect: true));
        sb.write(field('URL', e.url));
        sb.write(field('Notes', e.notes));
        if (e.totp.isNotEmpty) sb.write(field('otp', e.totp));
        sb.write('</Entry>');
      }
    }

    entries(byFolder[''] ?? []);
    for (final f in byFolder.entries.where((e) => e.key.isNotEmpty)) {
      sb.write('<Group><Name>${escapeXml(f.key)}</Name>');
      entries(f.value);
      sb.write('</Group>');
    }
    sb.write('</Group></Root></KeePassFile>');
    return sb.toString();
  }
}
