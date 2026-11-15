part of 'import_parsers.dart';


class _Parser {
  final ImpJob j;
  _Parser(this.j);

  final List<ImpNote> out = [];
  final Map<String, ImpRes> _files = {}; // путь файла → вложение
  Map<String, String> _vault = {}; // имя файла (нижний регистр) → путь (Obsidian)

  static const _exts = {
    'md': ['md', 'markdown'], 'mdfm': ['md', 'markdown'], 'obsidian': ['md'],
    'html': ['html', 'htm'], 'txt': ['txt'], 'enex': ['enex'],
  };

  List<ImpNote> run() {
    final ok = _exts[j.kind] ?? const <String>[];
    if (j.dir) {
      final root = Directory(j.paths.first);
      final top = root.path.replaceAll('\\', '/').split('/').where((x) => x.isNotEmpty).last;
      final all = root.listSync(recursive: true, followLinks: false).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (j.kind == 'obsidian') {
        for (final f in all) {
          if (!f.path.replaceAll('\\', '/').contains('/.obsidian/') && !ok.contains(_ext(f.path))) {
            _vault[_base(f.path).toLowerCase() + '.' + _ext(f.path)] = f.path;
          }
        }
      }
      for (final f in all) {
        final rel = f.path.substring(root.path.length).replaceAll('\\', '/');
        if (rel.contains('/.obsidian/') || rel.contains('/.trash/')) continue;
        if (!ok.contains(_ext(f.path))) continue;
        final dirs = rel.split('/').where((x) => x.isNotEmpty).toList()..removeLast();
        _one(f, j.kind == 'enex' ? [top] : [top, ...dirs]);
      }
    } else {
      for (final p in j.paths) {
        _one(File(p), const []);
      }
    }
    return out;
  }

  void _one(File f, List<String> folder) {
    try {
      switch (j.kind) {
        case 'enex':
          _enex(f, folder.isEmpty ? [_base(f.path)] : folder);
          break;
        case 'html':
          _html(f, folder);
          break;
        case 'txt':
          final t = _read(f).replaceAll('\r\n', '\n');
          out.add(ImpNote(_base(f.path), t.split('\n').map((l) => l.trim().isEmpty ? l : '$l  ').join('\n'),
              created: f.lastModifiedSync().millisecondsSinceEpoch, folder: folder));
          break;
        default:
          _md(f, folder);
      }
    } catch (_) {
      // повреждённый или нечитаемый файл пропускаем
    }
  }

  // ---------------------------------------------------------------- вложения

  /// Локальный файл как вложение (кэшируется, чтобы одна картинка не дублировалась).
  ImpRes? _local(String path) {
    final hit = _files[path];
    if (hit != null) return hit;
    final f = File(path);
    if (!f.existsSync()) return null;
    final name = path.replaceAll('\\', '/').split('/').last;
    final r = ImpRes(newId(), name, _mimes[_ext(name)] ?? 'application/octet-stream', f.readAsBytesSync());
    _files[path] = r;
    return r;
  }

  String _relPath(File note, String src) {
    final d = note.parent.path;
    return '$d${Platform.pathSeparator}${Uri.decodeFull(src).replaceAll('/', Platform.pathSeparator)}';
  }

  // ---------------------------------------------------------------- Markdown

  static final _img = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');

  void _md(File f, List<String> folder) {
    var text = _read(f).replaceAll('\r\n', '\n');
    var title = '';
    final tags = <String>[];
    var created = f.lastModifiedSync().millisecondsSinceEpoch;
    final fm = j.kind == 'mdfm' || j.kind == 'obsidian';
    if (fm && text.startsWith('---\n')) {
      final end = text.indexOf('\n---', 4);
      if (end > 0) {
        final head = text.substring(4, end);
        text = text.substring(end + 4).replaceFirst(RegExp(r'^\n'), '');
        String? listKey;
        for (final ln in head.split('\n')) {
          final m = RegExp(r'^([A-Za-z_]+):\s*(.*)$').firstMatch(ln);
          if (m != null) {
            listKey = null;
            final k = m.group(1)!.toLowerCase(), v = m.group(2)!.trim();
            if (k == 'title') title = v.replaceAll(RegExp('^["\']|["\']\$'), '');
            if (k == 'tags' || k == 'tag') {
              if (v.isEmpty) {
                listKey = 'tags';
              } else {
                tags.addAll(v.replaceAll(RegExp(r'[\[\]]'), '').split(',').map((x) => x.trim().replaceAll('#', '')).where((x) => x.isNotEmpty));
              }
            }
            if (k == 'created' || k == 'date') {
              final d = DateTime.tryParse(v.replaceAll('"', ''));
              if (d != null) created = d.millisecondsSinceEpoch;
            }
          } else if (listKey != null) {
            final t = ln.trim().replaceFirst(RegExp(r'^-\s*'), '').replaceAll('#', '');
            if (t.isNotEmpty) tags.add(t);
          }
        }
      }
    }
    if (title.isEmpty) {
      final m = RegExp(r'^\s*#[ \t]+([^\n]+)\n?').firstMatch(text);
      if (m != null) {
        title = m.group(1)!.trim();
        text = text.substring(m.end);
      } else {
        title = _base(f.path);
      }
    }
    final res = <ImpRes>[];
    if (j.kind == 'obsidian') {
      text = text.replaceAllMapped(RegExp(r'!\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]'), (m) {
        final p = _vault[m.group(1)!.trim().toLowerCase()];
        final r = p == null ? null : _local(p);
        if (r == null) return m.group(0)!;
        res.add(r);
        return '![${r.name}](:/${r.id})';
      });
      text = text.replaceAllMapped(RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]'),
          (m) => (m.group(2) ?? m.group(1)!).trim());
      for (final m in RegExp(r'(?:^|\s)#([\p{L}][\p{L}\p{N}_/\-]*)', unicode: true).allMatches(text)) {
        final t = m.group(1)!;
        if (!tags.contains(t) && tags.length < 12) tags.add(t);
      }
    }
    text = text.replaceAllMapped(_img, (m) {
      final src = m.group(2)!;
      if (RegExp(r'^(https?:|data:|:/)').hasMatch(src)) return m.group(0)!;
      final r = _local(_relPath(f, src));
      if (r == null) return m.group(0)!;
      res.add(r);
      return '![${m.group(1)}](:/${r.id})';
    });
    out.add(ImpNote(title, text, tags: tags, created: created, folder: folder, res: res));
  }

  // ---------------------------------------------------------------- HTML

  void _html(File f, List<String> folder) {
    var h = _read(f);
    var title = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(h)?.group(1)?.trim() ?? '';
    if (title.isEmpty) {
      title = RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true).firstMatch(h)?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
    }
    if (title.isEmpty) title = _base(f.path);
    final res = <ImpRes>[];
    h = h.replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), '');
    h = h.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');
    h = h.replaceAllMapped(RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2''', caseSensitive: false), (m) {
      final src = m.group(3)!;
      if (RegExp(r'^(https?:|data:|:/)').hasMatch(src)) return m.group(0)!;
      final r = _local(_relPath(f, src));
      if (r == null) return m.group(0)!;
      res.add(r);
      return '${m.group(1)}":/${r.id}"';
    });
    out.add(ImpNote(_unxml(title), JexParse.htmlToMd(h).trim(),
        created: f.lastModifiedSync().millisecondsSinceEpoch, folder: folder, res: res));
  }

  // ---------------------------------------------------------------- Evernote ENEX

  static int _enexDate(String? s) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$').firstMatch((s ?? '').trim());
    if (m == null) return 0;
    int g(int i) => int.parse(m.group(i)!);
    return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).millisecondsSinceEpoch;
  }

  static String? _tag(String src, String name) =>
      RegExp('<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name>').firstMatch(src)?.group(1);

  void _enex(File f, List<String> folder) {
    final text = _read(f);
    for (final nm in RegExp(r'<note>([\s\S]*?)</note>').allMatches(text)) {
      final src = nm.group(1)!;
      final title = _unxml((_tag(src, 'title') ?? '').trim());
      var content = _tag(src, 'content') ?? '';
      final cd = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(content);
      content = cd != null ? cd.group(1)! : _unxml(content);

      final byHash = <String, ImpRes>{};
      final order = <ImpRes>[];
      for (final rm in RegExp(r'<resource>([\s\S]*?)</resource>').allMatches(src)) {
        final r = rm.group(1)!;
        final b64 = (_tag(r, 'data') ?? '').replaceAll(RegExp(r'\s'), '');
        if (b64.isEmpty) continue;
        Uint8List bytes;
        try {
          bytes = base64Decode(b64);
        } catch (_) {
          continue;
        }
        final mime = (_tag(r, 'mime') ?? 'application/octet-stream').trim();
        var name = _unxml((_tag(r, 'file-name') ?? '').trim());
        if (name.isEmpty) name = 'file.${mime.split('/').last}';
        final res = ImpRes(newId(), name, mime, bytes);
        byHash[md5Hex(bytes)] = res;
        order.add(res);
      }
      final used = <ImpRes>[];
      var next = 0;
      content = content.replaceAllMapped(RegExp(r'<en-media\b([^>]*?)/?>(?:</en-media>)?'), (m) {
        final attrs = m.group(1)!;
        final hash = RegExp(r'hash="([0-9a-fA-F]+)"').firstMatch(attrs)?.group(1)?.toLowerCase();
        var r = hash == null ? null : byHash[hash];
        r ??= next < order.length ? order[next] : null;
        next++;
        if (r == null) return '';
        used.add(r);
        return r.mime.startsWith('image/')
            ? '<img src=":/${r.id}" alt="${r.name}"/>'
            : '<a href=":/${r.id}">${r.name}</a>';
      });
      for (final r in order) {
        if (!used.contains(r)) used.add(r);
      }
      content = content
          .replaceAll(RegExp(r'<\?xml[^>]*\?>|<!DOCTYPE[^>]*>', caseSensitive: false), '')
          .replaceAllMapped(RegExp(r'<en-todo\b([^>]*?)/?>'),
              (m) => m.group(1)!.contains('checked="true"') ? '[x] ' : '[ ] ')
          .replaceAll(RegExp(r'</?en-note[^>]*>'), '');
      final tags = RegExp(r'<tag>([\s\S]*?)</tag>').allMatches(src).map((m) => _unxml(m.group(1)!.trim())).where((t) => t.isNotEmpty).toList();
      out.add(ImpNote(title, JexParse.htmlToMd(content).trim(),
          tags: tags, created: _enexDate(_tag(src, 'created')), folder: folder, res: used));
    }
  }
}