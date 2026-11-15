# CODEMAP — карта файлов

_Создаётся автоматически: `python3 tools/codemap.py`. Описания: `tools/file_notes.txt`._

## Ядро

- **lib/applog.dart** (123) Встроенный журнал ошибок и событий (AppLog.I.i/e) — `LogEntry, AppLog`
- **lib/bg_sync.dart** (63) Фоновая синхронизация Android через WorkManager (bgDispatcher, BgSync.apply) — `BgSync`
- **lib/connect.dart** (100) Экран подключения хранилища и аккаунта ASRbox (двухуровневая авторизация) — `ConnectScreen`
- **lib/crypto.dart** (101) AES-256-GCM, PBKDF2; encrypt/decrypt, encryptJson/decryptJson в изолятах — `Crypto`
- **lib/diag_screens.dart** (265) История синхронизации и журнал ошибок — `SyncHistoryScreen, LogScreen, DiagHub`
- **lib/gdrive.dart** (287) Google Диск как хранилище (Drive API, OAuth) — `GDrive, GDriveRemote`
- **lib/hub.dart** (88) Связи между модулями (открыть заметку/событие из другого раздела) — `Hub`
- **lib/lock.dart** (174) Экран входа, создание профиля, пароль, биометрия — `LockScreen`
- **lib/main.dart** (205) Точка входа, тема, MaterialApp.builder (масштаб, компактный вид, глобальная строка статуса) — `App`
- **lib/md5.dart** (64) MD5 для сопоставления вложений Evernote (не для защиты данных) — `md5Hex()`
- **lib/models.dart** (214) Все модели данных: Note, Block, TableData, CalEvent, PassEntry, Group, Settings, ChatMsg — `Cell, Merge, TableData, CheckItem`
- **lib/notify.dart** (162) Уведомления и напоминания (Android/Windows) — `Notifier`
- **lib/settings_screen.dart** (178) Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт) — `SettingsScreen`
- **lib/store.dart** (95) Главное хранилище состояния: профили, ключи, заметки, события, чат, сохранение, поиск, блокировки модулей, запуск синхронизации — `ProfileInfo, Store`
- **lib/util.dart** (168) Утилиты: runPool, writeAtomic/readValid, saveBytes, toast, isDesktop — `setSecure, writeAtomic, saveBytes, toast, copyClear, csvEscape()`

## Синхронизация и хранилища

- **lib/accounts.dart** (129) Реестр аккаунтов ASRbox на хранилище (accounts/<uid>.json), проверка пароля, синхронизация настроек (список _skip — что не едет между устройствами) — `Accounts`
- **lib/merge.dart** (179) Трёхстороннее слияние заметок по блокам/строкам/ячейкам (mergeNotes)
- **lib/remote.dart** (243) Remote (WebDAV Dav, LocalRemote), счётчики и журнал сети Net — `NetEvent, Net, Remote, Dav`
- **lib/sync.dart** (195) SyncService: обмен с сервером (заметки, события, папки, группы, вложения, чат, комментарии, пароли) — `SyncService`
- **lib/synchist.dart** (131) Статистика и история синхронизации, отмена — `SyncCancelled, CancelToken, SyncStats, SyncRecord`

## Интерфейс и оболочка

- **lib/app_menu.dart** (167) Верхнее меню компьютерного вида (Файл · Вид · Переход · Блокноты · Заметка · Сервис · Помощь), импорт/экспорт из меню — `MenuHandlers, AppMenu`
- **lib/ctx_menu.dart** (58) Контекстное меню: CtxItem, showCtx, CtxArea (правая кнопка / долгое нажатие) — `CtxItem, CtxArea`
- **lib/panes.dart** (125) ThreePane: три блока с перестановкой и изменением ширины — `PaneSpec, ThreePane`
- **lib/shell.dart** (283) Оболочка: вкладки, боковое меню (телефон), левая панель (компьютер), модули — `Shell`
- **lib/status_strip.dart** (106) Глобальная строка статуса синхронизации (на любом экране) — `StatusStrip`
- **lib/transfer_screen.dart** (89) Подробный журнал передачи данных — `TransferScreen`
- **lib/widgets.dart** (167) Общие виджеты: Pal, AppCard, Avatar, TagChip, Fab — `Pal, AppCard, SectionTitle, Hint, Avatar, TagChip`

## Заметки

- **lib/desktop_notes.dart** (299) Компьютерный вид заметок в три блока (папки | список | редактор), горячие клавиши — `DesktopNotes`
- **lib/editor.dart** (164) Редактор заметки (блоки, меню, экспорт, встраиваемый режим) — `EditorScreen`
- **lib/formula.dart** (231) Вычисление формул таблиц (A1, диапазоны, функции) — `Evaluator`
- **lib/import_formats.dart** (158) Реестр форматов импорта (JEX, RAW, ENEX, HTML, MD, MD+Front Matter, Obsidian, TXT, ONE) и запуск импорта с выбором файла/каталога — `ImportFormat, Importer`
- **lib/import_model.dart** (94) Промежуточная заметка импорта (ImpNote) и запись её в хранилище (commitImport) — `ImpRes, ImpNote`
- **lib/import_parsers.dart** (64) Разбор форматов импорта в фоновом изоляте (impParse): Markdown, Obsidian, HTML, TXT, Evernote ENEX — `ImpJob`
- **lib/local_tx.dart** (11) Заглушка локальной расшифровки голоса (подменяется в сборке whisper) — `LocalTx`
- **lib/md.dart** (262) Разбор Markdown в блоки и отображение (MdDoc) — `MdBlock, MdPara, MdHeading, MdCode, MdQuote, MdHr`
- **lib/md_editor.dart** (291) Текстовый блок с панелью форматирования — `MdTextBlock`
- **lib/md_ops.dart** (230) Операции форматирования Markdown над выделением (жирный, списки, ссылки) — `MdOps, MdListFormatter`
- **lib/media.dart** (252) Блоки изображений, файлов и голоса — `ImageBlockView`
- **lib/note_actions.dart** (175) Действия над заметками и папками для контекстного меню — `NoteActions`
- **lib/notes_page.dart** (168) Список заметок (мобильный вид), главная — `NotesList`
- **lib/pdf_export.dart** (80) Экспорт заметок в PDF (пакет pdf, шрифт DejaVu) — `PdfExport`
- **lib/table_screen.dart** (133) Редактор таблиц — `TableScreen`
- **lib/transcribe.dart** (25) Облачная расшифровка голоса (Whisper-совместимый API) — `Transcriber`
- **lib/trash_screen.dart** (95) Корзина (30 дней) — `TrashScreen`
- **lib/xlsx.dart** (157) Импорт и экспорт .xlsx — `Xlsx`

## Общая папка

- **lib/chat_page.dart** (206) Общий чат группы: шифрованные сообщения, опрос, отправка — `ChatPage`
- **lib/comments_view.dart** (137) Комментарии к общим заметкам — `CommentsView`
- **lib/groups.dart** (224) Группы: создание, приглашения, права, вступление, профили участников — `Groups`
- **lib/shared_page.dart** (273) Раздел «Общая папка»: группы, приглашения, участники — `SharedPage`

## Пароли

- **lib/autofill.dart** (241) Автозаполнение Android: запрос и экран выбора записи пароля — `AutofillRequest, AutofillPicker`
- **lib/pass_io.dart** (267) Импорт/экспорт паролей: Bitwarden, KeePass, LastPass, CSV — `PassIO`
- **lib/pass_page.dart** (183) Экран паролей: мобильный список и компьютерный вид в три блока, карточка записи — `PassPage`
- **lib/pass_store.dart** (240) Хранилище паролей (свой мастер-пароль и ключ) — `PassStore`
- **lib/totp.dart** (54) Одноразовые коды TOTP — `base32Decode, extractSecret, totpCode, totpSecondsLeft()`

## Календарь

- **lib/calendar_page.dart** (143) Экран календаря (месяц/список событий и задач) — `CalendarPage`
- **lib/event_screen.dart** (216) Экран события / задачи — `EventScreen`
- **lib/google.dart** (153) Синхронизация с Google Календарём — `GoogleCal`
- **lib/ics.dart** (114) Импорт и экспорт календаря .ics — `Ics`

## Бэкап

- **lib/backup.dart** (283) Backup (полный бэкап профиля, страховочные копии safety/), Jex (импорт/экспорт Joplin JEX, экспорт Markdown, bodyOf/bodyLines) — `Backup, JexResource, JexFolder, JexNote, JexParsed`
- **lib/backup_page.dart** (167) Экран «Бэкап»: приложение и настройки / телефон (кнопка +, восстановление архива телефона) — `BackupPage`
- **lib/phone_data.dart** (293) Данные телефона Android: звонки, контакты, SMS, Wi-Fi; сбор и восстановление архива — `PhoneData`

## Платформа

- **lib/desktop.dart** (168) Windows: трей, сворачивание, окно-напоминание — `Desktop`

## Без области

- **lib/app_dirs.dart** (69) Каталог данных приложения. В портативном режиме Windows (файл `portable.txt` — `AppDirs`
- **lib/backup_2.dart** (228) Формат JEX — tar-архив с файлами «<id>.md» (заметки, папки, теги) и — `Jex`
- **lib/backup_3.dart** (10) (нет описания — добавьте в tools/file_notes.txt)
- **lib/backup_4.dart** (219) (нет описания — добавьте в tools/file_notes.txt) — `JexParse`
- **lib/backup_5.dart** (247) (нет описания — добавьте в tools/file_notes.txt) — `JexIo`
- **lib/backup_page_2.dart** (271) (нет описания — добавьте в tools/file_notes.txt)
- **lib/calendar_page_2.dart** (261) (нет описания — добавьте в tools/file_notes.txt)
- **lib/calendar_page_3.dart** (97) (нет описания — добавьте в tools/file_notes.txt)
- **lib/calendars.dart** (233) Описание календаря: локальный (хранится только в приложении и в синхронизации ASRbox) — `CalDef, Cals, CalendarsBox`
- **lib/connect_2.dart** (263) (нет описания — добавьте в tools/file_notes.txt)
- **lib/connect_3.dart** (99) (нет описания — добавьте в tools/file_notes.txt)
- **lib/dictation.dart** (130) Диктовка: запись → расшифровка → буфер обмена. Используется страницей «Диктовка» и — `Dictation`
- **lib/dock.dart** (247) Режим «Док» (по мотивам RocketDock): окно превращается в узкую панель значков у края экрана, — `DockMode, DockView, DockPage`
- **lib/dock_2.dart** (164) (нет описания — добавьте в tools/file_notes.txt)
- **lib/edit_cmd.dart** (109) Активный Markdown-блок: меню «Правка» применяет к нему форматирование. — `ActiveMd, EditCmd`
- **lib/edit_menu.dart** (50) Меню «Правка» верхней панели (как в Joplin). Пункты форматирования — `EditMenu`
- **lib/editor_2.dart** (240) (нет описания — добавьте в tools/file_notes.txt)
- **lib/editor_3.dart** (257) (нет описания — добавьте в tools/file_notes.txt)
- **lib/editor_4.dart** (94) (нет описания — добавьте в tools/file_notes.txt)
- **lib/folder_sync.dart** (262) Правило «папка или файл → сервер»: односторонняя выгрузка (зеркало без удаления). — `FolderSync, FolderSyncBox`
- **lib/google_2.dart** (203) (нет описания — добавьте в tools/file_notes.txt) — `GoogleSync`
- **lib/groups_2.dart** (149) (нет описания — добавьте в tools/file_notes.txt) — `GroupsInvite`
- **lib/ical_sub.dart** (110) Подписка на онлайн-календарь по ссылке iCal (.ics / webcal://), только чтение. — `IcalSub`
- **lib/ics_2.dart** (210) «Сырые» события VEVENT: список «свойство → значение», где ключ — имя вместе с параметрами — `IcsRaw`
- **lib/ics_block.dart** (101) Блок заметки «Календарь (.ics)»: файл календаря открыт списком, одно событие — одна строка — `IcsBlockView`
- **lib/ics_block_2.dart** (247) (нет описания — добавьте в tools/file_notes.txt)
- **lib/import_parsers_2.dart** (254) (нет описания — добавьте в tools/file_notes.txt)
- **lib/lock_2.dart** (205) (нет описания — добавьте в tools/file_notes.txt)
- **lib/md_2.dart** (47) (нет описания — добавьте в tools/file_notes.txt)
- **lib/md_3.dart** (284) Картинка из вложения (`:/id`) или из интернета.
- **lib/md_4.dart** (53) (нет описания — добавьте в tools/file_notes.txt)
- **lib/md_lines.dart** (92) Строчные операции меню «Правка» (как в Joplin): удалить/дублировать/переместить — `MdLines`
- **lib/media_2.dart** (50) (нет описания — добавьте в tools/file_notes.txt) — `FileBlockView, VoiceBlockView`
- **lib/media_3.dart** (254) (нет описания — добавьте в tools/file_notes.txt)
- **lib/mini_calendar.dart** (114) Мини-календарь месяца (7 колонок, ячейки 28 px, сегодня — индиго-кружок, точки у дней с событиями). — `MiniCalendar`
- **lib/model_dl.dart** (240) Собственная загрузка моделей Whisper (ggml): с прогрессом, отменой, докачкой — `ModelDl, ModelBox`
- **lib/models_2.dart** (127) Папка заметок (поддерживается вложенность через parent). — `Block, Version, NoteFolder`
- **lib/models_3.dart** (221) (нет описания — добавьте в tools/file_notes.txt) — `Note, Comment`
- **lib/models_4.dart** (266) Общая папка (группа): отдельное хранилище WebDAV, своя папка и свой ключ шифрования — `CalEvent, PassEntry, Group`
- **lib/models_5.dart** (284) (нет описания — добавьте в tools/file_notes.txt) — `Settings`
- **lib/models_6.dart** (164) Сообщение чата общей группы. Хранится как отдельный зашифрованный файл — `ExtSettings1, ChatMsg`
- **lib/notes_page_2.dart** (244) (нет описания — добавьте в tools/file_notes.txt)
- **lib/notes_page_3.dart** (151) (нет описания — добавьте в tools/file_notes.txt)
- **lib/pass_page_2.dart** (256) (нет описания — добавьте в tools/file_notes.txt)
- **lib/pass_page_3.dart** (238) (нет описания — добавьте в tools/file_notes.txt)
- **lib/pass_page_4.dart** (192) (нет описания — добавьте в tools/file_notes.txt) — `PassEntryScreen`
- **lib/pass_page_5.dart** (212) (нет описания — добавьте в tools/file_notes.txt)
- **lib/remote_2.dart** (83) Обычная папка на устройстве (внешний диск, папка, которую синхронизирует другая программа). — `LocalRemote`
- **lib/schedule_panel.dart** (237) Правая панель «Расписание»: вертикальный таймлайн выбранного дня — `SchedulePanel`
- **lib/schedule_panel_2.dart** (98) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_2.dart** (259) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_3.dart** (252) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_4.dart** (77) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_5.dart** (248) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_6.dart** (51) Мастер разрешений Android: батарея, автозапуск, инструкции по брендам. — `showPermissionWizard()`
- **lib/settings_screen_7.dart** (111) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_8.dart** (71) (нет описания — добавьте в tools/file_notes.txt)
- **lib/settings_screen_9.dart** (182) (нет описания — добавьте в tools/file_notes.txt)
- **lib/shared_page_2.dart** (275) Внутри группы: Чат и Заметки (полный функционал заметок с комментариями). — `GroupScreen`
- **lib/shared_page_3.dart** (249) Участники группы. Создатель может ограничить редактирование и удалить участника. — `MembersScreen`
- **lib/shell_2.dart** (247) (нет описания — добавьте в tools/file_notes.txt)
- **lib/shell_3.dart** (249) Окно-напоминание (Windows): висит, пока не закроют, со звуком.
- **lib/sidebar.dart** (187) Левая панель компьютерного вида (260 px): «Новая заметка», мини-календарь, — `Sidebar`
- **lib/store_2.dart** (243) (нет описания — добавьте в tools/file_notes.txt) — `ExtStore1`
- **lib/store_3.dart** (247) (нет описания — добавьте в tools/file_notes.txt) — `ExtStore2`
- **lib/store_4.dart** (250) (нет описания — добавьте в tools/file_notes.txt) — `ExtStore3`
- **lib/store_5.dart** (211) (нет описания — добавьте в tools/file_notes.txt) — `ExtStore4`
- **lib/sync_2.dart** (220) (нет описания — добавьте в tools/file_notes.txt) — `SyncScopes`
- **lib/sync_3.dart** (272) (нет описания — добавьте в tools/file_notes.txt) — `SyncChat`
- **lib/table_screen_2.dart** (252) (нет описания — добавьте в tools/file_notes.txt)
- **lib/theme.dart** (168) Палитра и тема приложения (минималистичный «нативный» стиль, как в Noteplan). — `AppColors`
- **lib/voice_page.dart** (127) Модуль «Диктовка»: зажмите кнопку (или нажмите для переключения), наговорите — текст — `VoicePage`
- **lib/win_module.dart** (196) Таблица клавиш для правил: код VK → название. — `WinService, WinPage`
- **lib/winsys.dart** (16) Заглушка системных функций Windows (глобальные клавиши и переназначение). — `WinSys`

## Тесты (tests/, при сборке копируются в test/)

- tests/asrbox_test.dart (193)
- tests/core_test.dart (185)
- tests/import_test.dart (163)
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
- tools/check_limit.py
- tools/codemap.py
- tools/make_icons.py
- .github/workflows/build.yml — CI: test, android, windows, linux, macos

Всего в lib/: 24006 строк.
