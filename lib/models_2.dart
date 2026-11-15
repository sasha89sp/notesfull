part of 'models.dart';


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