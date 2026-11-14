# ARCHITECTURE

## Общая схема
Один Flutter-пакет, все файлы в `lib/` (плоско). Состояние живёт в `Store` (ChangeNotifier): профиль, ключи, заметки, события, папки, чат, комментарии, настройки. Модули приложения (разделы) — это экраны поверх `Store`; полной изоляции между ними пока нет (связи — через `Store` и `hub.dart`).

## Области (см. карту файлов в CODEMAP.md)
| Область | Что входит |
|---|---|
| Ядро | models, store, crypto, util, lock, connect, settings_screen, notify, applog, bg_sync, main |
| Синхронизация | sync, merge, synchist, remote, accounts, gdrive |
| Интерфейс | shell, panes, ctx_menu, status_strip, widgets, transfer_screen |
| Заметки | notes_page, desktop_notes, editor, md*, media, table_screen, formula, xlsx, pdf_export, trash_screen, note_actions |
| Общая папка | shared_page, groups, chat_page, comments_view |
| Пароли | pass_page, pass_store, pass_io, totp, autofill |
| Календарь | calendar_page, event_screen, ics, google |
| Бэкап | backup, backup_page, phone_data |
| Платформа | desktop (Windows) |

## Ключевые механизмы
- **Профили и ключи.** Пароль → PBKDF2 → локальный ключ `key` (шифрует файлы профиля `*.enc`) и ключ синхронизации `syncKey` (один на все устройства аккаунта). Биометрия: ключи в `FlutterSecureStorage` (`Store.unlockBio`, `unlockSilent` для фона).
- **Хранение.** `Store._saveJson` → шифрование (`Crypto.encryptJson` в изоляте для больших списков) → `writeAtomic` (tmp → rename, `.bak`). Чтение через `readValid` (откат на `.bak`).
- **Remote.** Абстракция хранилища: `Dav` (WebDAV), `LocalRemote` (папка), `GDriveRemote`. Все запросы считаются в `Net` (скорость, журнал).
- **Синхронизация.** `SyncService.run`: настройки → заметки (`_scope`: manifest.json, параллельные запросы через `runPool`, слияние `mergeNotes`, конфликт → копия «(конфликт)») → события/папки (`_mergeBlob`, «новее побеждает») → группы (свой Remote и ключ у каждой) → вложения. Корзина: 30 дней (`kTrashDays`).
- **Группы.** `Group` (id, ключ, права view/edit/own, участники); приглашения `invites/<id>.json` с отметкой использования; чат и комментарии — отдельные зашифрованные файлы.
- **Виды.** `Store.useDesktop(width)`: Settings.uiMode auto/desktop/mobile. Компьютерный вид: левая панель в `shell.dart`, `ThreePane` для заметок и паролей, `main.dart` строит глобальный `StatusStrip`, масштаб 0.88 и Ctrl+колесо.
- **Платформенный код Android** добавляется скриптами `ci/patch_*.py` при сборке (папка android/ в репозитории не хранится; `flutter create` выполняется в CI).

## Правила кода
1. Новые файлы — маленькие (≤ 300 строк), с `///`-описанием наверху; строку про файл добавить в `tools/file_notes.txt`.
2. Любое изменение заметки обновляет `updatedAt` (иначе синхронизация его не отправит); блоки различаются по `id` (иначе не работает слияние).
3. Данные пишутся только через `Store._saveJson` / `writeAtomic`.
4. Сетевые вызовы — только через `Remote` (попадают в строку статуса и журнал).
5. Новые поля `Settings` добавлять в конструктор, `toJson`, `fromJson`; если настройка устройственная — добавить в `_skip` (`accounts.dart`).
6. Перед рискованными операциями вызывать `Backup.safetyCopy(store, причина)`.
7. Пакеты pub добавлять только после согласования с владельцем.
8. Тесты — в `tests/` (при сборке копируются в `test/`).

## План (по возрастанию риска)
1. Документы и инструменты (сделано): HANDOFF, ARCHITECTURE, DECISIONS, CODEMAP, brief/apply.
2. Дробить большие файлы по ходу задач (models, store, pass_page, settings_screen, backup, editor), выносить виды блоков и форматы экспорта в реестры.
3. Разложить `lib/` по подпапкам-областям (core/, notes/, shared/, pass/, calendar/, backup/), не меняя поведения.
4. Контракт ядра и отдельные модули — когда проект вырастет (≈100 тыс. строк) или появится второй крупный модуль. Тогда: иерархические карты, `MODULE.md` у каждого модуля, версионирование данных.
