part of 'settings_screen.dart';

extension _ExtSettingsWidgetsD on _SettingsScreenState {
  List<Widget> _widgetsD() => [
          const SectionTitle('Безопасность'),
          if (bioAvail)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Вход по биометрии'),
              subtitle: const Text('Ключ хранится в защищённом хранилище системы'),
              value: st.bio,
              onChanged: _bio,
            ),
          _field('lock', 'Автоблокировка паролей, секунд',
              type: TextInputType.number),

          if (Platform.isAndroid) ...[
            const SectionTitle('Напоминания на Android'),
            const Hint(
                'Чтобы напоминания приходили на телефонах с агрессивной экономией батареи '
                '(Xiaomi, Huawei, Honor, Motorola с китайской прошивкой), отключите оптимизацию батареи '
                'и разрешите автозапуск.'),
            OutlinedButton(
              onPressed: () => showPermissionWizard(context, s),
              child: const Text('Открыть мастер настройки'),
            ),
            const SectionTitle('Автозаполнение паролей'),
            FutureBuilder<bool>(
              future: autofillSupported(),
              builder: (context, snap) {
                if (snap.data != true) {
                  return const Hint(
                      'Автозаполнение есть в сборке «autofill» (android-apk-autofill).');
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Hint(
                          'Выберите «Заметки» сервисом автозаполнения в настройках Android. '
                          'При входе в другие приложения откроется список ваших паролей.'),
                      OutlinedButton(
                        onPressed: () => const AndroidIntent(
                                action: 'android.settings.REQUEST_SET_AUTOFILL_SERVICE',
                                data: 'package:com.mysecure.mysecure_notes')
                            .launch(),
                        child: const Text('Включить автозаполнение'),
                      ),
                    ]);
              },
            ),
          ],

          const SectionTitle('История синхронизации'),
          const Hint('Дата, статус, сколько данных отправлено и получено, куда и подробный журнал.'),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DiagHub(store: s, tab: 1))),
            child: const Text('Открыть историю'),
          ),

          const SectionTitle('Резервная копия и перенос'),
          const Hint('Бэкап содержит все данные профиля, включая пароли и вложения, в зашифрованном виде. '
              'Joplin: заметки, папки, теги и вложения (формат JEX). Календарь: файлы .ics.'),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton(onPressed: _backup, child: const Text('Полный бэкап')),
            OutlinedButton(onPressed: _restore, child: const Text('Восстановить')),
            OutlinedButton(onPressed: _safetyList, child: const Text('Страховочные копии')),
            OutlinedButton(
                onPressed: () => _upload(null), child: const Text('Бэкап на сервер сейчас')),
            OutlinedButton(onPressed: _remoteBackups, child: const Text('Бэкапы на сервере')),
            OutlinedButton(onPressed: _jexImport, child: const Text('Импорт из Joplin')),
            OutlinedButton(onPressed: () => Importer.pick(context, s), child: const Text('Импорт заметок (все форматы)')),
            OutlinedButton(onPressed: _jexExport, child: const Text('Экспорт в Joplin')),
            OutlinedButton(onPressed: _mdExport, child: const Text('Экспорт в Markdown')),
            OutlinedButton(onPressed: _pdfExport, child: const Text('Экспорт всех заметок в PDF')),
            OutlinedButton(onPressed: _icsImport, child: const Text('Импорт календаря')),
            OutlinedButton(onPressed: _icsExport, child: const Text('Экспорт календаря')),
          ]),
          const SizedBox(height: 12),
          const Text('Бэкап на WebDAV', style: TextStyle(fontWeight: FontWeight.w600)),
          const Hint('Бэкап зашифрован вашим паролем, на сервер он уходит в том же виде. '
              'Можно использовать то хранилище, куда вы вошли, или отдельный WebDAV только для бэкапов.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('После создания бэкапа загружать на сервер'),
            subtitle: const Text('Всё происходит автоматически, без лишних действий',
                style: TextStyle(fontSize: 12)),
            value: st.bkAuto,
            onChanged: (v) {
              setState(() => st.bkAuto = v);
              _autoNow();
            },
          ),
          if (st.bkAuto)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Делать бэкап сам раз в сутки'),
              subtitle: const Text('При запуске и во время работы приложения',
                  style: TextStyle(fontSize: 12)),
              value: st.bkDaily,
              onChanged: (v) {
                setState(() => st.bkDaily = v);
                _autoNow();
              },
            ),
          _drop('Сервер для бэкапов', st.bkStorage,
              const {
                'same': 'Текущее хранилище',
                'custom': 'Другой WebDAV (в т.ч. Яндекс Диск)',
                'gdrive': 'Google Диск'
              },
              (v) => st.bkStorage = v),
          if (st.bkStorage == 'custom')
            const Hint('Яндекс Диск: адрес https://webdav.yandex.ru, логин — ваш логин Яндекса, '
                'пароль — «пароль приложения» (id.yandex.ru → Безопасность → Пароли приложений).'),
          if (st.bkStorage == 'gdrive') ...[
            const Hint('Google Диск: используются Client ID и Secret из раздела «Google Календарь» '
                '(OAuth-клиент типа «Компьютер», в проекте включён Drive API). '
                'Приложение видит только созданные им файлы (доступ drive.file).'),
            OutlinedButton(
              onPressed: () async {
                _apply();
                try {
                  await GDrive.authorize(s);
                  if (mounted) {
                    setState(() {});
                    toast(context, 'Google Диск подключён');
                  }
                } catch (e) {
                  if (mounted) toast(context, 'Не удалось войти: $e');
                }
              },
              child: Text(st.gdRefresh.isEmpty
                  ? 'Войти в Google Диск'
                  : 'Google Диск подключён · войти заново'),
            ),
          ],
          if (st.bkStorage == 'custom') ...[
            _field('bkUrl', 'Адрес WebDAV для бэкапов'),
            _field('bkUser', 'Логин'),
            _field('bkPass', 'Пароль приложения', obscure: true),
            _field('bkFolder', 'Папка на сервере'),
          ],
          _drop('Хранить копий', '${st.bkKeep}',
              const {'3': '3', '7': '7', '14': '14', '30': '30'},
              (v) => st.bkKeep = int.tryParse(v) ?? 7),
          if (st.bkLast > 0)
            Hint('Последняя загрузка: ${fmtDate(st.bkLast)}'),
          const Hint('Импорт и экспорт паролей (CSV и другие форматы) находятся во вкладке «Пароли», меню ⋮.'),

          const SectionTitle('Шифрование'),
          const Hint('Три независимых ключа:\n'
              '1. Общее — ключ из логина и пароля профиля: заметки, календарь, настройки и всё остальное, кроме паролей и общей папки.\n'
              '2. Общая папка — отдельный ключ, создаётся вместе с папкой и входит в приглашение.\n'
              '3. Пароли — отдельный мастер-пароль, задаётся при создании хранилища паролей.'),

          const SectionTitle('Сохранение'),
          const Hint('Настройки сохраняются сами; кнопка записывает только настройки и не запускает синхронизацию.'),
          FilledButton.icon(
              onPressed: _saveOnly,
              icon: const Icon(Icons.check),
              label: const Text('Сохранить настройки')),

          const SectionTitle('Сброс'),
          const Hint('Удаляет этот профиль с устройства: заметки, события, пароли, ключи и вложения. '
              'Данные в облаке остаются. Для возврата понадобится снова войти в хранилище.'),
          OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Pal.error(context)),
              onPressed: _reset,
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Сбросить профиль')),

          const SectionTitle('Отладка и диагностика'),
          const Hint('Журнал ошибок, сбоев и зависаний с причинами; его можно сохранить файлом.'),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DiagHub(store: s, tab: 2))),
            child: const Text('Открыть журнал и процессы'),
          ),
      ];
}
