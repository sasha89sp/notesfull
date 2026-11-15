part of 'models.dart';


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
        case 'ics':
          sb.write('📅 календарь  ');
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