part of 'backup.dart';

class JexParse {


  // ------------------------------------------------------------ импорт

  /// Разбор «заголовок + тело + свойства». Свойства — блок «ключ: значение» в конце.
  static (String, String, Map<String, String>) splitItem(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var i = lines.length - 1;
    while (i >= 0 && lines[i].trim().isEmpty) {
      i--;
    }
    final props = <String, String>{};
    final re = RegExp(r'^([A-Za-z_]+): ?(.*)$');
    while (i >= 0 && lines[i].trim().isNotEmpty) {
      final m = re.firstMatch(lines[i]);
      if (m == null) break;
      props[m.group(1)!] = m.group(2)!;
      i--;
    }
    // оставшееся: заголовок, пустая строка, тело
    final rest = lines.sublist(0, i < 0 ? 0 : i + 1);
    var title = '';
    var body = '';
    if (props.containsKey('type_') && props['type_'] == '6') {
      return ('', '', props);
    }
    if (rest.isNotEmpty) {
      title = rest.first;
      var from = 1;
      if (from < rest.length && rest[from].trim().isEmpty) from++;
      body = rest.sublist(from < rest.length ? from : rest.length).join('\n').trim();
    }
    return (title, body, props);
  }

  static JexParsed parse(List<int> tarBytes) {
    final res = JexParsed();
    final ar = TarDecoder().decodeBytes(tarBytes);
    final resMeta = <String, Map<String, String>>{};
    final resFiles = <String, List<int>>{};
    final tags = <String, String>{}; // id → название
    final links = <String, List<String>>{}; // note → tag ids

    for (final f in ar.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      final content = f.content as List<int>;
      if (name.startsWith('resources/')) {
        final base = name.substring('resources/'.length);
        final dot = base.indexOf('.');
        resFiles[dot < 0 ? base : base.substring(0, dot)] = content;
        continue;
      }
      if (!name.endsWith('.md')) continue;
      final (title, body, p) = splitItem(utf8.decode(content, allowMalformed: true));
      final type = p['type_'] ?? '';
      final id = p['id'] ?? name.substring(0, name.length - 3);
      switch (type) {
        case '1':
          res.notes.add(JexNote(
            id,
            title,
            body,
            p['parent_id'] ?? '',
            Jex._pick(p, 'user_created_time', 'created_time'),
            Jex._pick(p, 'user_updated_time', 'updated_time'),
            [],
            isTodo: p['is_todo'] == '1',
            todoDue: Jex._parseDue(p['todo_due']),
            todoDone: Jex._parseDue(p['todo_completed']) > 0,
            markup: int.tryParse(p['markup_language'] ?? '1') ?? 1,
            sourceUrl: p['source_url'] ?? '',
            lat: Jex._d(p['latitude']),
            lon: Jex._d(p['longitude']),
            deleted: Jex._parseDue(p['deleted_time']) > 0,
            conflict: p['is_conflict'] == '1',
          ));
          break;
        case '2':
          res.folders.add(JexFolder(id, title, p['parent_id'] ?? ''));
          break;
        case '4':
          resMeta[id] = {...p, 'title': title};
          break;
        case '5':
          tags[id] = title;
          break;
        case '6':
          links.putIfAbsent(p['note_id'] ?? '', () => []).add(p['tag_id'] ?? '');
          break;
        default:
          res.skipped++;
      }
    }
    for (final n in res.notes) {
      for (final tid in links[n.id] ?? const <String>[]) {
        final t = tags[tid];
        if (t != null && t.isNotEmpty) n.tags.add(t);
      }
    }
    for (final e in resFiles.entries) {
      final m = resMeta[e.key];
      final name = m == null
          ? e.key
          : ((m['title'] ?? '').isNotEmpty ? m['title']! : (m['filename'] ?? e.key));
      res.resources[e.key] =
          JexResource(e.key, name, m?['mime'] ?? 'application/octet-stream', e.value);
    }
    return res;
  }

  static final RegExp _ref = RegExp(r'!?\[([^\]]*)\]\(:/([0-9a-fA-F]{32})[^)]*\)');
  static final RegExp _check = RegExp(r'^\s*[-*]\s+\[( |x|X)\]\s?(.*)$');

  /// Markdown → блоки. [att] превращает вложение Joplin в блок (или null, если файла нет).
  static List<Block> toBlocks(String body, Block? Function(String resId) att) {
    final blocks = <Block>[];
    final text = <String>[];
    final items = <CheckItem>[];

    void flushText() {
      final t = text.join('\n').trim();
      if (t.isNotEmpty) blocks.add(Block(type: 'text', content: t));
      text.clear();
    }

    void flushItems() {
      if (items.isNotEmpty) {
        blocks.add(Block(type: 'checklist', items: List.of(items)));
      }
      items.clear();
    }

    for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
      final c = _check.firstMatch(line);
      if (c != null) {
        flushText();
        items.add(CheckItem(c.group(2) ?? '', c.group(1) != ' '));
        continue;
      }
      flushItems();
      if (_ref.hasMatch(line)) {
        flushText();
        for (final m in _ref.allMatches(line)) {
          final b = att(m.group(2)!.toLowerCase());
          if (b != null) blocks.add(b);
        }
        final rest = line.replaceAll(_ref, '').trim();
        if (rest.isNotEmpty) text.add(rest);
      } else {
        text.add(line);
      }
    }
    flushItems();
    flushText();
    if (blocks.isEmpty) blocks.add(Block(type: 'text'));
    return blocks;
  }

  /// HTML-заметки Joplin (markup_language = 2) → Markdown, чтобы форматирование сохранилось.
  static String htmlToMd(String html) {
    var s = html.replaceAll('\r\n', '\n');
    String tag(String name, String open, [String? close]) {
      return s.replaceAllMapped(
          RegExp('<$name(?:\\s[^>]*)?>(.*?)</$name>', caseSensitive: false, dotAll: true),
          (m) => '$open${m.group(1)}${close ?? open}');
    }

    s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    s = s.replaceAllMapped(
        RegExp(r'<img\b[^>]*?src="([^"]*)"[^>]*?(?:alt="([^"]*)")?[^>]*>', caseSensitive: false),
        (m) => '![${m.group(2) ?? ''}](${m.group(1)})');
    s = s.replaceAllMapped(
        RegExp(r'<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true),
        (m) => '[${m.group(2)}](${m.group(1)})');
    for (var i = 1; i <= 6; i++) {
      s = s.replaceAllMapped(
          RegExp('<h$i(?:\\s[^>]*)?>(.*?)</h$i>', caseSensitive: false, dotAll: true),
          (m) => '\n\n${'#' * i} ${m.group(1)}\n\n');
    }
    s = tag('strong', '**');
    s = tag('b', '**');
    s = tag('em', '*');
    s = tag('i', '*');
    s = tag('del', '~~');
    s = tag('s', '~~');
    s = tag('u', '++');
    s = tag('mark', '==');
    s = tag('code', '`');
    s = s.replaceAllMapped(
        RegExp(r'<pre(?:\s[^>]*)?>(.*?)</pre>', caseSensitive: false, dotAll: true),
        (m) => '\n```\n${m.group(1)!.replaceAll(RegExp(r'</?code[^>]*>'), '')}\n```\n');
    s = s.replaceAllMapped(
        RegExp(r'<li(?:\s[^>]*)?>(.*?)</li>', caseSensitive: false, dotAll: true),
        (m) => '\n- ${m.group(1)!.trim()}');
    s = s.replaceAllMapped(
        RegExp(r'<blockquote(?:\s[^>]*)?>(.*?)</blockquote>', caseSensitive: false, dotAll: true),
        (m) => '\n${m.group(1)!.trim().split('\n').map((l) => '> $l').join('\n')}\n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n\n---\n\n');
    s = s.replaceAll(RegExp(r'</(p|div|ul|ol|table|tr)>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' | ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static final RegExp _idRef = RegExp(r':/([0-9a-fA-F]{32})');
}
