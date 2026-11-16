// ▸ Часть models.dart: Все модели данных: Note, Block, TableData, CalEvent, PassEntry, Group, Settings, ChatMsg  [содержит: ExtSettings1, ChatMsg]
part of 'models.dart';

extension ExtSettings1 on Settings {

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
        'modLock': modLock,
        'fontScale': fontScale,
        'uiMode': uiMode,
        'paneOrder': paneOrder,
        'paneW': paneW,
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
        'bkPhoneEvery': bkPhoneEvery,
        'bgSync': bgSync,
        'syncOnStart': syncOnStart,
        'showSchedule': showSchedule,
        'syncOnResume': syncOnResume,
        'syncOnNet': syncOnNet,
        'syncOnChange': syncOnChange,
        'syncEvery': syncEvery,
        'gcalEvery': gcalEvery,
        'txModelSrc': txModelSrc,
        'platform': platform,
        'remapOn': remapOn,
        'remaps': remaps,
        'dictGlobal': dictGlobal,
        'dictKeys': dictKeys,
        'dockItems': dockItems,
        'dockPos': dockPos,
        'dockSize': dockSize,
        'dockZoom': dockZoom,
        'dockOpacity': dockOpacity,
        'dockOnTop': dockOnTop,
        'folderSyncs': folderSyncs,
        'calendars': calendars,
        'stripPos': stripPos,
        'navMode': navMode,
        'sharedEvery': sharedEvery,
        'sharedComments': sharedComments,
        'sharedOnOpen': sharedOnOpen,
        'sharedLast': sharedLast,
        'gcalLast': gcalLast,
        'bkPhoneLast': bkPhoneLast,
        'bkLast': bkLast,
        'settingsUpdatedAt': settingsUpdatedAt,
      };

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