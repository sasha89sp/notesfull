# CODEMAP — карта файлов

_Создаётся автоматически: `python3 tools/codemap.py`. Описания: `tools/file_notes.txt`._

## Ядро

- **lib/applog.dart** (123) Встроенный журнал ошибок и событий (AppLog.I.i/e) — `LogEntry, AppLog`
- **lib/bg_sync.dart** (63) Фоновая синхронизация Android через WorkManager (bgDispatcher, BgSync.apply) — `BgSync`
- **lib/connect.dart** (450) Экран подключения хранилища и аккаунта ASRbox (двухуровневая авторизация) — `ConnectScreen`
- **lib/crypto.dart** (101) AES-256-GCM, PBKDF2; encrypt/decrypt, encryptJson/decryptJson в изолятах — `Crypto`
- **lib/diag_screens.dart** (189) История синхронизации и журнал ошибок — `SyncHistoryScreen, LogScreen`
- **lib/gdrive.dart** (287) Google Диск как хранилище (Drive API, OAuth) — `GDrive, GDriveRemote`
- **lib/hub.dart** (88) Связи между модулями (открыть заметку/событие из другого раздела) — `Hub`
- **lib/lock.dart** (373) Экран входа, создание профиля, пароль, биометрия — `LockScreen`
- **lib/main.dart** (219) Точка входа, тема, MaterialApp.builder (масштаб, компактный вид, глобальная строка статуса) — `App`
- **lib/md5.dart** (64) MD5 для сопоставления вложений Evernote (не для защиты данных) — `md5Hex()`
- **lib/models.dart** (1161) Все модели данных: Note, Block, TableData, CalEvent, PassEntry, Group, Settings, ChatMsg — `Cell, Merge, TableData, CheckItem, Block, Version`
- **lib/notify.dart** (162) Уведомления и напоминания (Android/Windows) — `Notifier`
- **lib/settings_screen.dart** (1110) Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт) — `SettingsScreen`
- **lib/store.dart** (985) Главное хранилище состояния: профили, ключи, заметки, события, чат, сохранение, поиск, блокировки модулей, запуск синхронизации — `ProfileInfo, Store`
- **lib/util.dart** (168) Утилиты: runPool, writeAtomic/readValid, saveBytes, toast, isDesktop — `setSecure, writeAtomic, saveBytes, toast, copyClear, csvEscape()`

## Синхронизация и хранилища

- **lib/accounts.dart** (129) Реестр аккаунтов ASRbox на хранилище (accounts/<uid>.json), проверка пароля, синхронизация настроек (список _skip — что не едет между устройствами) — `Accounts`
- **lib/merge.dart** (179) Трёхстороннее слияние заметок по блокам/строкам/ячейкам (mergeNotes)
- **lib/remote.dart** (317) Remote (WebDAV Dav, LocalRemote), счётчики и журнал сети Net — `NetEvent, Net, Remote, Dav, LocalRemote`
- **lib/sync.dart** (650) SyncService: обмен с сервером (заметки, события, папки, группы, вложения, чат, комментарии, пароли) — `SyncService`
- **lib/synchist.dart** (131) Статистика и история синхронизации, отмена — `SyncCancelled, CancelToken, SyncStats, SyncRecord`

## Интерфейс и оболочка

- **lib/app_menu.dart** (156) Верхнее меню компьютерного вида (Файл · Вид · Переход · Блокноты · Заметка · Сервис · Помощь), импорт/экспорт из меню — `MenuHandlers, AppMenu`
- **lib/ctx_menu.dart** (58) Контекстное меню: CtxItem, showCtx, CtxArea (правая кнопка / долгое нажатие) — `CtxItem, CtxArea`
- **lib/panes.dart** (125) ThreePane: три блока с перестановкой и изменением ширины — `PaneSpec, ThreePane`
- **lib/shell.dart** (753) Оболочка: вкладки, боковое меню (телефон), левая панель (компьютер), модули — `Shell`
- **lib/status_strip.dart** (98) Глобальная строка статуса синхронизации (на любом экране) — `StatusStrip`
- **lib/transfer_screen.dart** (88) Подробный журнал передачи данных — `TransferScreen`
- **lib/widgets.dart** (157) Общие виджеты: Pal, AppCard, Avatar, TagChip, Fab — `Pal, AppCard, SectionTitle, Hint, Avatar, TagChip`

## Заметки

- **lib/desktop_notes.dart** (299) Компьютерный вид заметок в три блока (папки | список | редактор), горячие клавиши — `DesktopNotes`
- **lib/editor.dart** (654) Редактор заметки (блоки, меню, экспорт, встраиваемый режим) — `EditorScreen`
- **lib/formula.dart** (231) Вычисление формул таблиц (A1, диапазоны, функции) — `Evaluator`
- **lib/import_formats.dart** (158) Реестр форматов импорта (JEX, RAW, ENEX, HTML, MD, MD+Front Matter, Obsidian, TXT, ONE) и запуск импорта с выбором файла/каталога — `ImportFormat, Importer`
- **lib/import_model.dart** (94) Промежуточная заметка импорта (ImpNote) и запись её в хранилище (commitImport) — `ImpRes, ImpNote`
- **lib/import_parsers.dart** (314) Разбор форматов импорта в фоновом изоляте (impParse): Markdown, Obsidian, HTML, TXT, Evernote ENEX — `ImpJob`
- **lib/local_tx.dart** (11) Заглушка локальной расшифровки голоса (подменяется в сборке whisper) — `LocalTx`
- **lib/md.dart** (607) Разбор Markdown в блоки и отображение (MdDoc) — `MdBlock, MdPara, MdHeading, MdCode, MdQuote, MdHr`
- **lib/md_editor.dart** (269) Текстовый блок с панелью форматирования — `MdTextBlock`
- **lib/md_ops.dart** (228) Операции форматирования Markdown над выделением (жирный, списки, ссылки) — `MdOps, MdListFormatter`
- **lib/media.dart** (544) Блоки изображений, файлов и голоса — `ImageBlockView, FileBlockView, VoiceBlockView`
- **lib/note_actions.dart** (175) Действия над заметками и папками для контекстного меню — `NoteActions`
- **lib/notes_page.dart** (548) Список заметок (мобильный вид), главная — `NotesList`
- **lib/pdf_export.dart** (80) Экспорт заметок в PDF (пакет pdf, шрифт DejaVu) — `PdfExport`
- **lib/table_screen.dart** (379) Редактор таблиц — `TableScreen`
- **lib/transcribe.dart** (25) Облачная расшифровка голоса (Whisper-совместимый API) — `Transcriber`
- **lib/trash_screen.dart** (95) Корзина (30 дней) — `TrashScreen`
- **lib/xlsx.dart** (157) Импорт и экспорт .xlsx — `Xlsx`

## Общая папка

- **lib/chat_page.dart** (206) Общий чат группы: шифрованные сообщения, опрос, отправка — `ChatPage`
- **lib/comments_view.dart** (137) Комментарии к общим заметкам — `CommentsView`
- **lib/groups.dart** (367) Группы: создание, приглашения, права, вступление, профили участников — `Groups`
- **lib/shared_page.dart** (790) Раздел «Общая папка»: группы, приглашения, участники — `SharedPage, GroupScreen, MembersScreen`

## Пароли

- **lib/autofill.dart** (241) Автозаполнение Android: запрос и экран выбора записи пароля — `AutofillRequest, AutofillPicker`
- **lib/pass_io.dart** (265) Импорт/экспорт паролей: Bitwarden, KeePass, LastPass, CSV — `PassIO`
- **lib/pass_page.dart** (1060) Экран паролей: мобильный список и компьютерный вид в три блока, карточка записи — `PassPage, PassEntryScreen`
- **lib/pass_store.dart** (240) Хранилище паролей (свой мастер-пароль и ключ) — `PassStore`
- **lib/totp.dart** (54) Одноразовые коды TOTP — `base32Decode, extractSecret, totpCode, totpSecondsLeft()`

## Календарь

- **lib/calendar_page.dart** (403) Экран календаря (месяц/список событий и задач) — `CalendarPage`
- **lib/event_screen.dart** (199) Экран события / задачи — `EventScreen`
- **lib/google.dart** (342) Синхронизация с Google Календарём — `GoogleCal`
- **lib/ics.dart** (111) Импорт и экспорт календаря .ics — `Ics`

## Бэкап

- **lib/backup.dart** (967) Backup (полный бэкап профиля, страховочные копии safety/), Jex (импорт/экспорт Joplin JEX, экспорт Markdown, bodyOf/bodyLines) — `Backup, JexResource, JexFolder, JexNote, JexParsed, Jex`
- **lib/backup_page.dart** (429) Экран «Бэкап»: приложение и настройки / телефон (кнопка +, восстановление архива телефона) — `BackupPage`
- **lib/phone_data.dart** (293) Данные телефона Android: звонки, контакты, SMS, Wi-Fi; сбор и восстановление архива — `PhoneData`

## Платформа

- **lib/desktop.dart** (168) Windows: трей, сворачивание, окно-напоминание — `Desktop`

## Тесты (tests/, при сборке копируются в test/)

- tests/asrbox_test.dart (193)
- tests/core_test.dart (185)
- tests/import_test.dart (69)
- tests/md_test.dart (141)
- tests/sync_test.dart (124)

## Сборка и вспомогательные скрипты

- ci/patch_android.py
- ci/patch_autofill.py
- ci/patch_backup.py
- ci/patch_macos.py
- ci/patch_windows.py
- tools/apply.py
- tools/brief.py
- tools/codemap.py
- tools/make_icons.py
- .github/workflows/build.yml — CI: test, android, windows, linux, macos

Всего в lib/: 19524 строк.

## Файлы больше 400 строк (кандидаты на дробление)

- lib/models.dart: 1161
- lib/settings_screen.dart: 1110
- lib/pass_page.dart: 1060
- lib/store.dart: 985
- lib/backup.dart: 967
- lib/shared_page.dart: 790
- lib/shell.dart: 753
- lib/editor.dart: 654
- lib/sync.dart: 650
- lib/md.dart: 607
- lib/notes_page.dart: 548
- lib/media.dart: 544
- lib/connect.dart: 450
- lib/backup_page.dart: 429
- lib/calendar_page.dart: 403
