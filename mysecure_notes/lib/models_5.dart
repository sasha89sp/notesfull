part of 'models.dart';


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
  String uiMode; // auto | desktop | mobile
  List<String> paneOrder; // порядок блоков десктопного вида: side, list, detail
  Map<String, double> paneW; // ширины боковых блоков
  double fontScale; // масштаб шрифта интерфейса (0.8–1.6)
  Map<String, int> modLock; // блокировка модуля биометрией: секунды бездействия (0 — при каждом входе)
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
  bool showSchedule; // панель «Расписание» справа (компьютерный вид)
  bool syncOnStart; // синхронизировать при запуске
  bool syncOnResume; // при возврате в приложение
  bool syncOnNet; // при появлении сети
  bool syncOnChange; // через 5 с после правок
  int syncEvery; // периодически, минуты (0 — выключено)
  List<Map<String, dynamic>> calendars; // календари (calendars.dart); пусто = «Основной» + Google
  List<Map<String, dynamic>> folderSyncs; // правила «папка/файл → сервер» (folder_sync.dart)
  bool remapOn; // Windows: переназначение клавиш включено
  List<Map<String, dynamic>> remaps; // [{from: vk, to: [vk...], on: bool}]
  bool dictGlobal; // Windows: диктовка по удержанию комбинации клавиш
  List<int> dictKeys; // коды VK комбинации диктовки
  List<Map<String, dynamic>> dockItems; // значки дока [{name, path, icon}]
  String dockPos; // bottom | top | left | right
  int dockSize; // размер значка, px
  double dockZoom; // увеличение при наведении
  double dockOpacity;
  bool dockOnTop;
  String platform; // платформа, на которой настройки последний раз сохранялись (для восстановления на другой)
  String txModelSrc; // источник моделей Whisper: hf | mirror
  String stripPos; // строка статуса: bottom | top | sync (снизу, только при синхронизации) | off
  String navMode; // нижнее меню (телефон): show | auto (прячется при прокрутке вниз) | hide
  int sharedEvery; // общие папки по расписанию, минуты (0 — только вручную)
  bool sharedComments; // комментарии общих папок при авто-синхронизации
  bool sharedOnOpen; // обновлять общую папку при её открытии
  int sharedLast;
  int gcalEvery; // Google Календарь по расписанию, минуты (0 — только вручную)
  int gcalLast; // когда Google Календарь синхронизировался в последний раз
  bool bgSync; // фоновая синхронизация Android (WorkManager)
  int bkPhoneEvery; // расписание бэкапа телефона: часы (0 — выключено)
  int bkPhoneLast; // когда делался последний бэкап телефона
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
    Map<String, int>? modLock,
    this.fontScale = 1.0,
    this.uiMode = 'auto',
    List<String>? paneOrder,
    Map<String, double>? paneW,
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
    this.bkPhoneEvery = 0,
    this.bgSync = false,
    this.syncOnStart = true,
    this.showSchedule = true,
    this.syncOnResume = false,
    this.syncOnNet = false,
    this.syncOnChange = true,
    this.syncEvery = 30,
    this.gcalEvery = 120,
    this.txModelSrc = 'hf',
    this.platform = '',
    this.remapOn = false,
    this.remaps = const [],
    this.dictGlobal = false,
    this.dictKeys = const [0xA2, 0xA0, 0x20],
    this.dockItems = const [],
    this.dockPos = 'bottom',
    this.dockSize = 48,
    this.dockZoom = 1.7,
    this.dockOpacity = 0.9,
    this.dockOnTop = true,
    this.folderSyncs = const [],
    this.calendars = const [],
    this.stripPos = 'bottom',
    this.navMode = 'show',
    this.sharedEvery = 15,
    this.sharedComments = true,
    this.sharedOnOpen = false,
    this.sharedLast = 0,
    this.gcalLast = 0,
    this.bkPhoneLast = 0,
    this.bkLast = 0,
    this.settingsUpdatedAt = 0,
  })  : attDone = attDone ?? [],
        groups = groups ?? [],
        modLock = modLock ?? {},
        paneOrder = paneOrder ?? ['side', 'list', 'detail'],
        paneW = paneW ?? {'side': 230, 'list': 330},
        favorites = favorites ?? [],
        pinned = pinned ?? [],
        modules = modules ??
            {'notes': true, 'shared': true, 'calendar': true, 'pass': true, 'voice': false, 'windows': false, 'dock': false, 'backup': true};

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
      bkPhoneEvery: (j['bkPhoneEvery'] ?? 0) as int,
      bgSync: (j['bgSync'] ?? false) as bool,
      syncOnStart: (j['syncOnStart'] ?? true) as bool,
      showSchedule: (j['showSchedule'] ?? true) as bool,
      syncOnResume: (j['syncOnResume'] ?? false) as bool,
      syncOnNet: (j['syncOnNet'] ?? false) as bool,
      syncOnChange: (j['syncOnChange'] ?? true) as bool,
      syncEvery: (j['syncEvery'] ?? 30) as int,
      gcalEvery: (j['gcalEvery'] ?? 120) as int,
      txModelSrc: (j['txModelSrc'] ?? 'hf') as String,
      platform: (j['platform'] ?? '') as String,
      remapOn: (j['remapOn'] ?? false) as bool,
      remaps: [for (final x in (j['remaps'] ?? []) as List) Map<String, dynamic>.from(x as Map)],
      dictGlobal: (j['dictGlobal'] ?? false) as bool,
      dictKeys: [for (final x in (j['dictKeys'] ?? [0xA2, 0xA0, 0x20]) as List) (x as num).toInt()],
      dockItems: [for (final x in (j['dockItems'] ?? []) as List) Map<String, dynamic>.from(x as Map)],
      dockPos: (j['dockPos'] ?? 'bottom') as String,
      dockSize: ((j['dockSize'] ?? 48) as num).toInt(),
      dockZoom: ((j['dockZoom'] ?? 1.7) as num).toDouble(),
      dockOpacity: ((j['dockOpacity'] ?? 0.9) as num).toDouble(),
      dockOnTop: (j['dockOnTop'] ?? true) as bool,
      calendars: [for (final m in (j['calendars'] ?? []) as List) Map<String, dynamic>.from(m as Map)],
      folderSyncs: [for (final m in (j['folderSyncs'] ?? []) as List) Map<String, dynamic>.from(m as Map)],
      stripPos: (j['stripPos'] ?? 'bottom') as String,
      navMode: (j['navMode'] ?? 'show') as String,
      sharedEvery: (j['sharedEvery'] ?? 15) as int,
      sharedComments: (j['sharedComments'] ?? true) as bool,
      sharedOnOpen: (j['sharedOnOpen'] ?? false) as bool,
      sharedLast: (j['sharedLast'] ?? 0) as int,
      gcalLast: (j['gcalLast'] ?? 0) as int,
      bkPhoneLast: (j['bkPhoneLast'] ?? 0) as int,
      bkLast: (j['bkLast'] ?? 0) as int,
      groups: ((j['groups'] ?? []) as List)
          .map((e) => Group.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      fontScale: ((j['fontScale'] ?? 1.0) as num).toDouble(),
      uiMode: (j['uiMode'] ?? 'auto') as String,
      paneOrder: ((j['paneOrder'] ?? ['side', 'list', 'detail']) as List).map((e) => e.toString()).toList(),
      paneW: ((j['paneW'] ?? {'side': 230, 'list': 330}) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      modLock: ((j['modLock'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      favorites: ((j['favorites'] ?? []) as List).map((e) => e.toString()).toList(),
      pinned: ((j['pinned'] ?? []) as List).map((e) => e.toString()).toList(),
      settingsUpdatedAt: (j['settingsUpdatedAt'] ?? 0) as int,
    );
  }}