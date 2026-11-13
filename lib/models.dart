import 'dart:convert';
import 'dart:math';
import 'local_tx.dart';

String newId() {
  final r = Random.secure();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(1 << 30).toRadixString(36)}';
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String two(int x) => x.toString().padLeft(2, '0');

const List<String> kMonths = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];
const List<String> kMonthsNom = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
];
const List<String> kWeekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${kMonths[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

String fmtDay(DateTime d) => '${d.day} ${kMonths[d.month - 1]} ${d.year}';
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------- Таблицы

class Cell {
  String v;
  int? bg;
  int? fg;
  Cell([this.v = '', this.bg, this.fg]);

  Map<String, dynamic> toJson() => {
        'v': v,
        if (bg != null) 'b': bg,
        if (fg != null) 'f': fg,
      };

  factory Cell.fromJson(Map<String, dynamic> j) =>
      Cell((j['v'] ?? '') as String, j['b'] as int?, j['f'] as int?);
}

class Merge {
  int r, c, rs, cs;
  Merge(this.r, this.c, this.rs, this.cs);

  Map<String, dynamic> toJson() => {'r': r, 'c': c, 'rs': rs, 'cs': cs};

  factory Merge.fromJson(Map<String, dynamic> j) =>
      Merge(j['r'] as int, j['c'] as int, j['rs'] as int, j['cs'] as int);

  bool covers(int rr, int cc) =>
      rr >= r && rr < r + rs && cc >= c && cc < c + cs;
}

class TableData {
  List<List<Cell>> cells;
  List<Merge> merges;
  TableData(this.cells, [List<Merge>? merges]) : merges = merges ?? [];

  factory TableData.empty(int rows, int cols) => TableData(
      List.generate(rows, (_) => List.generate(cols, (_) => Cell())));

  int get rows => cells.length;
  int get cols => cells.isEmpty ? 0 : cells[0].length;

  Map<String, dynamic> toJson() => {
        'cells': cells.map((r) => r.map((c) => c.toJson()).toList()).toList(),
        'merges': merges.map((m) => m.toJson()).toList(),
      };

  factory TableData.fromJson(Map<String, dynamic> j) => TableData(
        ((j['cells'] ?? []) as List)
            .map((r) => (r as List)
                .map((c) => Cell.fromJson(Map<String, dynamic>.from(c as Map)))
                .toList())
            .toList(),
        ((j['merges'] ?? []) as List)
            .map((m) => Merge.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );

  bool get isEmpty => cells.every((r) => r.every((c) => c.v.trim().isEmpty));

  Merge? mergeAt(int r, int c) {
    for (final m in merges) {
      if (m.covers(r, c)) return m;
    }
    return null;
  }

  void insertRow(int at) {
    cells.insert(at, List.generate(cols, (_) => Cell()));
    for (final m in merges) {
      if (m.r >= at) {
        m.r++;
      } else if (at < m.r + m.rs) {
        m.rs++;
      }
    }
  }

  void insertCol(int at) {
    for (final r in cells) {
      r.insert(at, Cell());
    }
    for (final m in merges) {
      if (m.c >= at) {
        m.c++;
      } else if (at < m.c + m.cs) {
        m.cs++;
      }
    }
  }

  void deleteRow(int at) {
    if (rows <= 1) return;
    cells.removeAt(at);
    final dead = <Merge>[];
    for (final m in merges) {
      if (m.r > at) {
        m.r--;
      } else if (m.r + m.rs > at) {
        if (m.rs == 1) {
          dead.add(m);
        } else {
          m.rs--;
        }
      }
    }
    merges.removeWhere(dead.contains);
  }

  void deleteCol(int at) {
    if (cols <= 1) return;
    for (final r in cells) {
      r.removeAt(at);
    }
    final dead = <Merge>[];
    for (final m in merges) {
      if (m.c > at) {
        m.c--;
      } else if (m.c + m.cs > at) {
        if (m.cs == 1) {
          dead.add(m);
        } else {
          m.cs--;
        }
      }
    }
    merges.removeWhere(dead.contains);
  }

  void mergeRange(int r1, int c1, int r2, int c2) {
    final rr1 = min(r1, r2), rr2 = max(r1, r2);
    final cc1 = min(c1, c2), cc2 = max(c1, c2);
    unmergeRange(rr1, cc1, rr2, cc2);
    if (rr1 == rr2 && cc1 == cc2) return;
    for (var r = rr1; r <= rr2; r++) {
      for (var c = cc1; c <= cc2; c++) {
        if (r != rr1 || c != cc1) cells[r][c].v = '';
      }
    }
    merges.add(Merge(rr1, cc1, rr2 - rr1 + 1, cc2 - cc1 + 1));
  }

  void unmergeRange(int r1, int c1, int r2, int c2) {
    merges.removeWhere((m) =>
        m.r <= max(r1, r2) &&
        m.r + m.rs - 1 >= min(r1, r2) &&
        m.c <= max(c1, c2) &&
        m.c + m.cs - 1 >= min(c1, c2));
  }
}

// ---------------------------------------------------------------- Блоки

/// type: text | checklist | quote | code | table | voice | image | file
class CheckItem {
  String text;
  bool done;
  CheckItem(this.text, [this.done = false]);

  Map<String, dynamic> toJson() => {'t': text, 'd': done};

  factory CheckItem.fromJson(Map<String, dynamic> j) =>
      CheckItem((j['t'] ?? '') as String, (j['d'] ?? false) as bool);
}

class Block {
  String id;
  String type;
  String content;
  List<CheckItem> items;
  Map<String, dynamic> meta;

  Block({
    String? id,
    required this.type,
    this.content = '',
    List<CheckItem>? items,
    Map<String, dynamic>? meta,
  })  : id = id ?? newId(),
        items = items ?? [],
        meta = meta ?? {};

  TableData get table => meta['table'] is Map
      ? TableData.fromJson(Map<String, dynamic>.from(meta['table'] as Map))
      : TableData.empty(3, 3);
  set table(TableData t) => meta['table'] = t.toJson();

  String? get att => meta['att'] as String?;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'content': content,
        'items': items.map((e) => e.toJson()).toList(),
        'meta': meta,
      };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        id: j['id'] as String?,
        type: (j['type'] ?? 'text') as String,
        content: (j['content'] ?? '') as String,
        items: ((j['items'] ?? []) as List)
            .map((e) => CheckItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        meta: j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : {},
      );

  Block copy() => Block(
        id: id,
        type: type,
        content: content,
        items: items.map((e) => CheckItem(e.text, e.done)).toList(),
        meta: Map<String, dynamic>.from(
            jsonDecode(jsonEncode(meta)) as Map<String, dynamic>),
      );

  bool get isEmpty {
    switch (type) {
      case 'checklist':
        return items.every((e) => e.text.trim().isEmpty);
      case 'table':
        return table.isEmpty;
      case 'voice':
      case 'image':
      case 'file':
        return false;
      default:
        return content.trim().isEmpty;
    }
  }
}

class Version {
  int at;
  String title;
  List<Block> blocks;
  Version({required this.at, required this.title, required this.blocks});

  Map<String, dynamic> toJson() => {
        'at': at,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory Version.fromJson(Map<String, dynamic> j) => Version(
        at: (j['at'] ?? 0) as int,
        title: (j['title'] ?? '') as String,
        blocks: ((j['blocks'] ?? []) as List)
            .map((e) => Block.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Папка заметок (поддерживается вложенность через parent).
class NoteFolder {
  String id;
  String name;
  String parent; // id родителя или пусто
  int updatedAt;
  bool deleted;
  NoteFolder({
    required this.id,
    required this.name,
    this.parent = '',
    required this.updatedAt,
    this.deleted = false,
  });

  factory NoteFolder.create(String name, String parent) =>
      NoteFolder(id: newId(), name: name, parent: parent, updatedAt: nowMs());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parent': parent,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory NoteFolder.fromJson(Map<String, dynamic> j) => NoteFolder(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        parent: (j['parent'] ?? '') as String,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        deleted: (j['deleted'] ?? false) as bool,
      );
}

final RegExp kAttRef = RegExp(r'\]\(:/([A-Za-z0-9]+)[\s)#]');

class Note {
  String id;
  String title;
  String vault; // personal | family
  String author;
  String authorId;
  String editor;
  int createdAt;
  int updatedAt;
  int syncedAt;
  bool deleted;
  bool favorite;
  List<String> tags;
  String folder; // id папки заметок (пусто — корень)
  List<Block> blocks;
  List<Version> history;
  List<Block>? base; // последнее синхронизированное состояние (для слияния)
  String baseTitle;

  Note({
    required this.id,
    this.title = '',
    this.vault = 'personal',
    this.author = '',
    this.authorId = '',
    this.editor = '',
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt = 0,
    this.deleted = false,
    this.favorite = false,
    this.folder = '',
    List<String>? tags,
    List<Block>? blocks,
    List<Version>? history,
    this.base,
    this.baseTitle = '',
  })  : tags = tags ?? [],
        blocks = blocks ?? [],
        history = history ?? [];

  /// Заметка общей папки (любой группы).
  bool get isGroup => vault != 'personal';

  /// Идентификаторы вложений, на которые ссылаются блоки и Markdown-текст (`![](:/id)`).
  Set<String> attachmentIds() {
    final out = <String>{};
    for (final b in blocks) {
      final a = b.att;
      if (a != null) out.add(a);
      if (b.type == 'text' || b.type == 'quote') {
        for (final r in kAttRef.allMatches(b.content)) {
          out.add(r.group(1)!);
        }
      }
    }
    return out;
  }

  factory Note.create(String author, String authorId, String vault) {
    final t = nowMs();
    return Note(
      id: newId(),
      vault: vault,
      author: author,
      authorId: authorId,
      editor: author,
      createdAt: t,
      updatedAt: t,
    );
  }

  bool get hasTable => blocks.any((b) => b.type == 'table');

  Map<String, dynamic> toJson({bool withHistory = true}) => {
        'id': id,
        'title': title,
        'vault': vault,
        'author': author,
        'authorId': authorId,
        'editor': editor,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'syncedAt': withHistory ? syncedAt : 0,
        'deleted': deleted,
        'favorite': favorite,
        'tags': tags,
        'folder': folder,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'history': withHistory ? history.map((v) => v.toJson()).toList() : [],
        'base': withHistory ? base?.map((b) => b.toJson()).toList() : null,
        'baseTitle': withHistory ? baseTitle : '',
      };

  void markSynced() {
    base = blocks.map((b) => b.copy()).toList();
    baseTitle = title;
  }

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        vault: (j['vault'] ?? 'personal') as String,
        author: (j['author'] ?? '') as String,
        authorId: (j['authorId'] ?? '') as String,
        editor: (j['editor'] ?? '') as String,
        createdAt: (j['createdAt'] ?? 0) as int,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        syncedAt: (j['syncedAt'] ?? 0) as int,
        deleted: (j['deleted'] ?? false) as bool,
        favorite: (j['favorite'] ?? false) as bool,
        tags: ((j['tags'] ?? []) as List).map((e) => e.toString()).toList(),
        folder: (j['folder'] ?? '') as String,
        blocks: ((j['blocks'] ?? []) as List)
            .map((e) => Block.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        history: ((j['history'] ?? []) as List)
            .map((e) => Version.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        base: j['base'] == null
            ? null
            : (j['base'] as List)
                .map((e) => Block.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
        baseTitle: (j['baseTitle'] ?? '') as String,
      );

  String preview(int max) {
    final sb = StringBuffer();
    for (final b in blocks) {
      switch (b.type) {
        case 'checklist':
          for (final i in b.items) {
            if (i.text.trim().isNotEmpty) {
              sb.write('${i.done ? '☑' : '☐'} ${i.text}  ');
            }
          }
          break;
        case 'table':
          sb.write('▦ таблица  ');
          break;
        case 'image':
          sb.write('🖼 фото  ');
          break;
        case 'file':
          sb.write('📎 ${b.meta['name'] ?? 'файл'}  ');
          break;
        case 'voice':
          sb.write('🎙 ${b.content.trim().isEmpty ? 'голосовая запись' : b.content}  ');
          break;
        default:
          if (b.content.trim().isNotEmpty) {
            sb.write('${b.content.replaceAll('\n', ' ')}  ');
          }
      }
      if (sb.length >= max) break;
    }
    final s = sb.toString().trim();
    return s.length > max ? s.substring(0, max) : s;
  }
}

// ---------------------------------------------------------------- Комментарии

class Comment {
  String id;
  String noteId;
  String authorId;
  String author;
  int at;
  String text;
  bool deleted;
  String file;
  bool synced;
  bool delSynced;

  Comment({
    required this.id,
    required this.noteId,
    required this.authorId,
    required this.author,
    required this.at,
    required this.text,
    this.deleted = false,
    this.file = '',
    this.synced = false,
    this.delSynced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'noteId': noteId,
        'authorId': authorId,
        'author': author,
        'at': at,
        'text': text,
        'deleted': deleted,
        'file': file,
        'synced': synced,
        'delSynced': delSynced,
      };

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'] as String,
        noteId: (j['noteId'] ?? '') as String,
        authorId: (j['authorId'] ?? '') as String,
        author: (j['author'] ?? '') as String,
        at: (j['at'] ?? 0) as int,
        text: (j['text'] ?? '') as String,
        deleted: (j['deleted'] ?? false) as bool,
        file: (j['file'] ?? '') as String,
        synced: (j['synced'] ?? false) as bool,
        delSynced: (j['delSynced'] ?? false) as bool,
      );
}

// ---------------------------------------------------------------- Календарь

class CalEvent {
  String id;
  String title;
  String notes;
  int start;
  int end;
  bool allDay;
  bool isTask;
  bool done;
  bool deleted;
  int remind; // минут до начала, -1 = нет
  String gId;
  int gSynced;
  int gLocal;
  String noteId; // заметка, из которой создано событие (связь модулей)
  int updatedAt;

  CalEvent({
    required this.id,
    this.title = '',
    this.notes = '',
    required this.start,
    required this.end,
    this.allDay = false,
    this.isTask = false,
    this.done = false,
    this.deleted = false,
    this.remind = -1,
    this.gId = '',
    this.gSynced = 0,
    this.gLocal = 0,
    this.noteId = '',
    required this.updatedAt,
  });

  factory CalEvent.create(DateTime at, {bool task = false}) {
    final s = DateTime(at.year, at.month, at.day, at.hour, 0)
        .add(const Duration(hours: 1));
    return CalEvent(
      id: newId(),
      start: s.millisecondsSinceEpoch,
      end: s.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      isTask: task,
      remind: task ? -1 : 15,
      updatedAt: nowMs(),
    );
  }

  DateTime get startDt => DateTime.fromMillisecondsSinceEpoch(start);
  DateTime get endDt => DateTime.fromMillisecondsSinceEpoch(end);

  /// Время срабатывания напоминания (или null)
  DateTime? get alarm =>
      remind < 0 ? null : startDt.subtract(Duration(minutes: remind));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'start': start,
        'end': end,
        'allDay': allDay,
        'isTask': isTask,
        'done': done,
        'deleted': deleted,
        'remind': remind,
        'gId': gId,
        'gSynced': gSynced,
        'gLocal': gLocal,
        'noteId': noteId,
        'updatedAt': updatedAt,
      };

  factory CalEvent.fromJson(Map<String, dynamic> j) => CalEvent(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        start: (j['start'] ?? 0) as int,
        end: (j['end'] ?? 0) as int,
        allDay: (j['allDay'] ?? false) as bool,
        isTask: (j['isTask'] ?? false) as bool,
        done: (j['done'] ?? false) as bool,
        deleted: (j['deleted'] ?? false) as bool,
        remind: (j['remind'] ?? -1) as int,
        gId: (j['gId'] ?? '') as String,
        gSynced: (j['gSynced'] ?? 0) as int,
        gLocal: (j['gLocal'] ?? 0) as int,
        noteId: (j['noteId'] ?? '') as String,
        updatedAt: (j['updatedAt'] ?? 0) as int,
      );
}

// ---------------------------------------------------------------- Пароли

class PassEntry {
  String id;
  String title;
  String username;
  String password;
  String url;
  String notes;
  String folder;
  String totp;
  bool favorite;
  bool deleted;
  bool isFolder; // служебная запись: пустая папка
  int updatedAt;
  List<Map<String, dynamic>> history; // {'p': пароль, 'at': время}

  PassEntry({
    required this.id,
    this.title = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.folder = '',
    this.totp = '',
    this.favorite = false,
    this.deleted = false,
    this.isFolder = false,
    required this.updatedAt,
    List<Map<String, dynamic>>? history,
  }) : history = history ?? [];

  factory PassEntry.create() => PassEntry(id: newId(), updatedAt: nowMs());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'folder': folder,
        'totp': totp,
        'favorite': favorite,
        'deleted': deleted,
        'isFolder': isFolder,
        'updatedAt': updatedAt,
        'history': history,
      };

  factory PassEntry.fromJson(Map<String, dynamic> j) => PassEntry(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        password: (j['password'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        folder: (j['folder'] ?? '') as String,
        totp: (j['totp'] ?? '') as String,
        favorite: (j['favorite'] ?? false) as bool,
        deleted: (j['deleted'] ?? false) as bool,
        isFolder: (j['isFolder'] ?? false) as bool,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        history: ((j['history'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

// ---------------------------------------------------------------- Настройки

/// Общая папка (группа): отдельное хранилище WebDAV, своя папка и свой ключ шифрования
/// (тип 2). Внутри — общие заметки с комментариями и чат.
class Group {
  String id;
  String name;
  String url;
  String user;
  String pass;
  String folder; // папка группы на сервере
  String key; // base64, 32 байта: ключ шифрования группы
  String owner; // profileId создателя
  bool legacy; // группа из прежней версии («Семья»): заметки с vault = 'family'
  bool removed; // владелец удалил меня из группы
  bool readOnly; // владелец ограничил мне редактирование

  Group({
    required this.id,
    this.name = '',
    this.url = '',
    this.user = '',
    this.pass = '',
    this.folder = '',
    this.key = '',
    this.owner = '',
    this.legacy = false,
    this.removed = false,
    this.readOnly = false,
  });

  /// Значение Note.vault для заметок группы.
  String get vault => legacy ? 'family' : 'g:$id';

  String get notesDir => '$folder/FamilyShared';
  String get chatDir => '$folder/chat';
  String get profilesDir => '$folder/profiles';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'user': user,
        'pass': pass,
        'folder': folder,
        'key': key,
        'owner': owner,
        'legacy': legacy,
        'removed': removed,
        'readOnly': readOnly,
      };

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        user: (j['user'] ?? '') as String,
        pass: (j['pass'] ?? '') as String,
        folder: (j['folder'] ?? '') as String,
        key: (j['key'] ?? '') as String,
        owner: (j['owner'] ?? '') as String,
        legacy: (j['legacy'] ?? false) as bool,
        removed: (j['removed'] ?? false) as bool,
        readOnly: (j['readOnly'] ?? false) as bool,
      );
}

class Settings {
  String url;
  String user;
  String pass;
  String familyPass;
  String author;
  String profileId;
  int color;
  String attMode; // wifi | any | off
  String photoQuality; // ask | high | mid | low | orig
  String txMode; // ask | local | api | off
  String txLocalModel; // tiny | base | small
  String kpPriv; // приватный X25519 (base64)
  String kpPub; // публичный X25519 (base64)
  String famKey; // семейный ключ (base64), если получен
  String txUrl;
  String txKey;
  String txModel;
  String txLang; // auto | ru | en
  String gClientId;
  String gSecret;
  String gRefresh;
  String gdRefresh; // токен Google Диска (отдельная область доступа)
  bool bio;
  bool wizardDone;
  int autoLock; // секунды (менеджер паролей)
  String theme; // system | light | dark
  List<String> attDone;
  bool verboseLog;
  String storage; // webdav | local
  String folder; // корневая папка данных на хранилище
  String localPath; // путь, если storage == local
  String userId; // идентификатор аккаунта ASRbox
  String grpUrl; // отдельный WebDAV общей группы (может отличаться от личного)
  String grpUser;
  String grpPass;
  String grpFolder;
  Map<String, bool> modules; // notes, shared, calendar, pass, backup
  List<Group> groups;
  List<String> favorites; // id заметок и папок в избранном (меню слева)
  List<String> pinned; // id заметок и папок, закреплённых на главной
  String bkStorage; // same — текущее хранилище, custom — отдельный WebDAV
  String bkUrl;
  String bkUser;
  String bkPass;
  String bkFolder;
  bool bkAuto; // после создания бэкапа загружать его на сервер
  bool bkDaily; // делать бэкап сам раз в сутки
  int bkKeep; // сколько последних копий хранить
  int bkLast;
  int settingsUpdatedAt;

  Settings({
    this.url = 'https://webdav.cloud.mail.ru',
    this.user = '',
    this.pass = '',
    this.familyPass = '',
    this.author = '',
    this.profileId = '',
    this.color = 0xFF007AFF,
    this.attMode = 'wifi',
    this.photoQuality = 'ask',
    this.txMode = 'ask',
    this.txLocalModel = 'base',
    this.kpPriv = '',
    this.kpPub = '',
    this.famKey = '',
    this.txUrl = 'https://api.openai.com/v1/audio/transcriptions',
    this.txKey = '',
    this.txModel = 'whisper-1',
    this.txLang = 'auto',
    this.gClientId = '',
    this.gSecret = '',
    this.gRefresh = '',
    this.gdRefresh = '',
    this.bio = false,
    this.wizardDone = false,
    this.autoLock = 90,
    this.theme = 'system',
    List<String>? attDone,
    this.verboseLog = false,
    this.storage = 'webdav',
    this.folder = '/MySecureApp',
    this.localPath = '',
    this.userId = '',
    this.grpUrl = '',
    this.grpUser = '',
    this.grpPass = '',
    this.grpFolder = '/ASRbox-Group',
    Map<String, bool>? modules,
    List<Group>? groups,
    List<String>? favorites,
    List<String>? pinned,
    this.bkStorage = 'same',
    this.bkUrl = '',
    this.bkUser = '',
    this.bkPass = '',
    this.bkFolder = '/ASRbox-Backups',
    this.bkAuto = false,
    this.bkDaily = false,
    this.bkKeep = 7,
    this.bkLast = 0,
    this.settingsUpdatedAt = 0,
  })  : attDone = attDone ?? [],
        groups = groups ?? [],
        favorites = favorites ?? [],
        pinned = pinned ?? [],
        modules = modules ??
            {'notes': true, 'shared': true, 'calendar': true, 'pass': true, 'backup': true};

  Map<String, dynamic> toJson() => {
        'url': url,
        'user': user,
        'pass': pass,
        'familyPass': familyPass,
        'author': author,
        'profileId': profileId,
        'color': color,
        'attMode': attMode,
        'photoQuality': photoQuality,
        'txMode': txMode,
        'txLocalModel': txLocalModel,
        'kpPriv': kpPriv,
        'kpPub': kpPub,
        'famKey': famKey,
        'txUrl': txUrl,
        'txKey': txKey,
        'txModel': txModel,
        'txLang': txLang,
        'gClientId': gClientId,
        'gSecret': gSecret,
        'gRefresh': gRefresh,
        'gdRefresh': gdRefresh,
        'bio': bio,
        'wizardDone': wizardDone,
        'autoLock': autoLock,
        'theme': theme,
        'attDone': attDone,
        'verboseLog': verboseLog,
        'storage': storage,
        'folder': folder,
        'localPath': localPath,
        'userId': userId,
        'grpUrl': grpUrl,
        'grpUser': grpUser,
        'grpPass': grpPass,
        'grpFolder': grpFolder,
        'modules': modules,
        'groups': groups.map((g) => g.toJson()).toList(),
        'favorites': favorites,
        'pinned': pinned,
        'bkStorage': bkStorage,
        'bkUrl': bkUrl,
        'bkUser': bkUser,
        'bkPass': bkPass,
        'bkFolder': bkFolder,
        'bkAuto': bkAuto,
        'bkDaily': bkDaily,
        'bkKeep': bkKeep,
        'bkLast': bkLast,
        'settingsUpdatedAt': settingsUpdatedAt,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    return Settings(
      url: (j['url'] ?? d.url) as String,
      user: (j['user'] ?? '') as String,
      pass: (j['pass'] ?? '') as String,
      familyPass: (j['familyPass'] ?? '') as String,
      author: (j['author'] ?? '') as String,
      profileId: (j['profileId'] ?? '') as String,
      color: (j['color'] ?? d.color) as int,
      attMode: (j['attMode'] ?? d.attMode) as String,
      photoQuality: (j['photoQuality'] ?? d.photoQuality) as String,
      txMode: (j['txMode'] ?? (LocalTx.available ? 'local' : d.txMode)) as String,
      txLocalModel: (j['txLocalModel'] ?? d.txLocalModel) as String,
      kpPriv: (j['kpPriv'] ?? '') as String,
      kpPub: (j['kpPub'] ?? '') as String,
      famKey: (j['famKey'] ?? '') as String,
      txUrl: (j['txUrl'] ?? d.txUrl) as String,
      txKey: (j['txKey'] ?? '') as String,
      txModel: (j['txModel'] ?? d.txModel) as String,
      txLang: (j['txLang'] ?? d.txLang) as String,
      gClientId: (j['gClientId'] ?? '') as String,
      gSecret: (j['gSecret'] ?? '') as String,
      gRefresh: (j['gRefresh'] ?? '') as String,
      gdRefresh: (j['gdRefresh'] ?? '') as String,
      bio: (j['bio'] ?? false) as bool,
      wizardDone: (j['wizardDone'] ?? false) as bool,
      autoLock: (j['autoLock'] ?? 90) as int,
      theme: (j['theme'] ?? 'system') as String,
      attDone: ((j['attDone'] ?? []) as List).map((e) => e.toString()).toList(),
      verboseLog: (j['verboseLog'] ?? false) as bool,
      storage: (j['storage'] ?? 'webdav') as String,
      folder: (j['folder'] ?? '/MySecureApp') as String,
      localPath: (j['localPath'] ?? '') as String,
      userId: (j['userId'] ?? '') as String,
      grpUrl: (j['grpUrl'] ?? '') as String,
      grpUser: (j['grpUser'] ?? '') as String,
      grpPass: (j['grpPass'] ?? '') as String,
      grpFolder: (j['grpFolder'] ?? d.grpFolder) as String,
      modules: {
        ...d.modules,
        ...((j['modules'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), v == true)),
      },
      bkStorage: (j['bkStorage'] ?? 'same') as String,
      bkUrl: (j['bkUrl'] ?? '') as String,
      bkUser: (j['bkUser'] ?? '') as String,
      bkPass: (j['bkPass'] ?? '') as String,
      bkFolder: (j['bkFolder'] ?? d.bkFolder) as String,
      bkAuto: (j['bkAuto'] ?? false) as bool,
      bkDaily: (j['bkDaily'] ?? false) as bool,
      bkKeep: (j['bkKeep'] ?? 7) as int,
      bkLast: (j['bkLast'] ?? 0) as int,
      groups: ((j['groups'] ?? []) as List)
          .map((e) => Group.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      favorites: ((j['favorites'] ?? []) as List).map((e) => e.toString()).toList(),
      pinned: ((j['pinned'] ?? []) as List).map((e) => e.toString()).toList(),
      settingsUpdatedAt: (j['settingsUpdatedAt'] ?? 0) as int,
    );
  }

  bool get syncConfigured => storage == 'local'
      ? localPath.isNotEmpty
      : storage == 'gdrive'
          ? gClientId.isNotEmpty && gSecret.isNotEmpty && gdRefresh.isNotEmpty
          : url.isNotEmpty && user.isNotEmpty && pass.isNotEmpty;
  bool get groupConfigured => grpUrl.isNotEmpty && grpUser.isNotEmpty && grpPass.isNotEmpty;
  bool moduleOn(String m) => modules[m] ?? true;
  bool get googleConfigured =>
      gClientId.isNotEmpty && gSecret.isNotEmpty && gRefresh.isNotEmpty;
}

// ---------------------------------------------------------------- Чаты

/// Сообщение чата общей группы. Хранится как отдельный зашифрованный файл
/// (семейным ключом) — сообщения только добавляются, поэтому конфликтов нет.
class ChatMsg {
  String id;
  String room;
  String authorId;
  String author;
  int at;
  String text;
  bool synced;

  ChatMsg({
    required this.id,
    this.room = 'general',
    this.authorId = '',
    this.author = '',
    required this.at,
    this.text = '',
    this.synced = false,
  });

  factory ChatMsg.create(String room, String authorId, String author, String text) =>
      ChatMsg(id: newId(), room: room, authorId: authorId, author: author, at: nowMs(), text: text);

  /// Имя файла на хранилище: время в начале, чтобы список сортировался.
  String get fileName => '${at.toString().padLeft(14, '0')}_$id.enc';

  Map<String, dynamic> toJson() => {
        'id': id,
        'room': room,
        'authorId': authorId,
        'author': author,
        'at': at,
        'text': text,
        'synced': synced,
      };

  /// Для отправки (без локального флага)
  Map<String, dynamic> toWire() => {
        'id': id,
        'room': room,
        'authorId': authorId,
        'author': author,
        'at': at,
        'text': text,
      };

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        id: j['id'] as String,
        room: (j['room'] ?? 'general') as String,
        authorId: (j['authorId'] ?? '') as String,
        author: (j['author'] ?? '') as String,
        at: (j['at'] ?? 0) as int,
        text: (j['text'] ?? '') as String,
        synced: (j['synced'] ?? false) as bool,
      );
}
