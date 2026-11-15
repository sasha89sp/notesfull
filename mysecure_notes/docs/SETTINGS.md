# Настройки: что синхронизируется, а что локально

Сгенерировано из `Settings.toJson` (lib/models.dart) и `Accounts._skip` (lib/accounts.dart). При добавлении поля решите, к какому типу оно относится, и при необходимости добавьте в `_skip`.

## Локальные (на каждом устройстве свои; не уезжают в аккаунт)
Подключения, пути, вид интерфейса, расписания, позиции панелей, Windows-модуль и док.

- `url`
- `user`
- `pass`
- `storage`
- `folder`
- `localPath`
- `userId`
- `modLock`
- `fontScale`
- `uiMode`
- `paneOrder`
- `paneW`
- `bgSync`
- `syncOnStart`
- `showSchedule`
- `syncOnResume`
- `syncOnNet`
- `syncOnChange`
- `syncEvery`
- `gcalEvery`
- `txModelSrc`
- `platform`
- `remapOn`
- `remaps`
- `dictGlobal`
- `dictKeys`
- `dockItems`
- `dockPos`
- `dockSize`
- `dockZoom`
- `dockOpacity`
- `dockOnTop`
- `folderSyncs`
- `stripPos`
- `navMode`
- `sharedEvery`
- `sharedComments`
- `sharedOnOpen`
- `sharedLast`
- `gcalLast`

## Общие (едут вместе с аккаунтом через WebDAV)

- `familyPass`
- `author`
- `profileId`
- `color`
- `attMode`
- `photoQuality`
- `txMode`
- `txLocalModel`
- `kpPriv`
- `kpPub`
- `famKey`
- `txUrl`
- `txKey`
- `txModel`
- `txLang`
- `gClientId`
- `gSecret`
- `gRefresh`
- `gdRefresh`
- `bio`
- `wizardDone`
- `autoLock`
- `theme`
- `attDone`
- `verboseLog`
- `grpUrl`
- `grpUser`
- `grpPass`
- `grpFolder`
- `modules`
- `groups`
- `favorites`
- `pinned`
- `bkStorage`
- `bkUrl`
- `bkUser`
- `bkPass`
- `bkFolder`
- `bkAuto`
- `bkDaily`
- `bkKeep`
- `bkPhoneEvery`
- `calendars`
- `bkPhoneLast`
- `bkLast`
- `settingsUpdatedAt`

## Бэкап и восстановление
Поле `platform` хранит ОС; при входе на другой ОС `Store._adaptToPlatform` сбрасывает uiMode, панели, bgSync, правила папок и localPath. Поля Windows-модуля и дока тоже стоит сбрасывать при смене ОС (пути значков не переносятся).
