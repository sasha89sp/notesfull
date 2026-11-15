part of 'models.dart';


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
  String calId; // календарь (пусто — по происхождению, см. Cals.idOf)
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
    this.calId = '',
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
        'calId': calId,
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
        calId: (j['calId'] ?? '') as String,
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
  String me; // мой идентификатор в этой группе (пусто — идентификатор профиля, у создателя)
  String myName; // имя, под которым я вошёл в группу
  String rights; // view (только просмотр) | edit (полное редактирование) | own (свои файлы + комментарии)
  String invId; // уникальный ID приглашения, по которому я вошёл

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
    this.me = '',
    this.myName = '',
    this.rights = 'edit',
    this.invId = '',
  });

  /// Идентификатор участника: у создателя — идентификатор профиля.
  String memberId(String profileId) => me.isEmpty ? profileId : me;

  /// Только просмотр: либо право «view», либо ограничение владельца.
  bool get viewOnly => readOnly || rights == 'view';

  /// Можно ли мне править эту заметку группы.
  bool canEditNote(Note n, String profileId) =>
      !viewOnly && (rights != 'own' || n.authorId == profileId || n.authorId.isEmpty);

  /// Комментарии разрешены всем, кроме режима «только просмотр».
  bool get canComment => rights != 'view' && !readOnly;

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
        'me': me,
        'myName': myName,
        'rights': rights,
        'invId': invId,
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
        me: (j['me'] ?? '') as String,
        myName: (j['myName'] ?? '') as String,
        rights: (j['rights'] ?? 'edit') as String,
        invId: (j['invId'] ?? '') as String,
      );
}