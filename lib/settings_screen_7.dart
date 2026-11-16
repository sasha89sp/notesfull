// ▸ Часть settings_screen.dart: Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт)  [содержит: _ExtSettingsWidgetsB]
part of 'settings_screen.dart';

extension _ExtSettingsWidgetsB on _SettingsScreenState {
  List<Widget> _widgetsB() => [
          const SectionTitle('Общая папка'),
          const Hint('Общие папки опрашиваются отдельно от личных данных: заметки, комментарии и чат '
              'проверяются по этим правилам. Свои несохранённые правки уходят сразу, '
              'а чат мгновенно при отправке сообщения.'),
          _drop('Проверять по расписанию', '${st.sharedEvery}',
              const {'0': 'Только вручную', '5': 'Каждые 5 минут', '15': 'Каждые 15 минут', '30': 'Каждые 30 минут', '60': 'Каждый час', '180': 'Каждые 3 часа'},
              (v) {
            st.sharedEvery = int.tryParse(v) ?? 0;
            _auto();
          }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Обновлять при открытии раздела'),
            value: st.sharedOnOpen,
            onChanged: (v) => setState(() {
              st.sharedOnOpen = v;
              _auto();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Комментарии при авто-синхронизации'),
            subtitle: const Text('Если выключить, комментарии обновляются только кнопкой синхронизации',
                style: TextStyle(fontSize: 12)),
            value: st.sharedComments,
            onChanged: (v) => setState(() {
              st.sharedComments = v;
              _auto();
            }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                st.sharedLast = 0;
                s.syncAll(scope: 'shared');
              },
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Обновить сейчас'),
            ),
          ),

          const SectionTitle('Модули'),
          const Hint('Отключённый модуль не загружается и не нагружает приложение. '
              'Связи работают и при отключённом модуле: например, событие, созданное '
              'из заметки, попадёт в календарь и напомнит о себе.'),
          for (final m in {
            'notes': 'Заметки',
            'shared': 'Общая папка',
            'calendar': 'Календарь',
            'pass': 'Пароли',
            'voice': 'Диктовка (голос → буфер обмена)',
            if (Platform.isWindows) 'windows': 'Windows (клавиши, диктовка по клавише)',
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) 'dock': 'Док (панель значков)',
            'backup': 'Бэкап',
          }.entries)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.value),
              value: st.moduleOn(m.key),
              onChanged: (v) {
                setState(() => st.modules[m.key] = v);
                _autoNow();
              },
            ),

          const SectionTitle('Блокировка разделов'),
          const Hint('Отдельная проверка биометрией или кодом устройства для общей папки и паролей. '
              'Время считается с момента выхода из раздела или сворачивания приложения.'),
          for (final m in {'shared': 'Общая папка', 'pass': 'Пароли'}.entries)
            _drop(
                m.value,
                st.modLock.containsKey(m.key) ? '${st.modLock[m.key]}' : 'off',
                const {
                  'off': 'Не блокировать',
                  '0': 'При каждом входе',
                  '30': 'Через 30 секунд',
                  '120': 'Через 2 минуты',
                  '600': 'Через 10 минут',
                },
                (v) {
                  if (v == 'off') {
                    st.modLock.remove(m.key);
                  } else {
                    st.modLock[m.key] = int.parse(v);
                    s.moduleLock(m.key);
                  }
                }),

          const SectionTitle('Фото'),
          _drop('Качество при добавлении', st.photoQuality, const {
            'ask': 'Спрашивать',
            'high': 'Высокое',
            'mid': 'Среднее',
            'low': 'Низкое',
            'orig': 'Исходное',
          }, (v) => st.photoQuality = v),

          const SectionTitle('Синхронизация заметок'),
          const Hint('Заметки, папки и теги обмениваются с сервером вместе со вложениями. '
              'Здесь — правила только для заметок; общие правила — в разделе «Синхронизация и бэкап».'),
          _drop('Вложения (фото, голос, файлы)', st.attMode,
              const {'wifi': 'Только Wi-Fi', 'any': 'Любая сеть', 'off': 'Не синхронизировать'},
              (v) => st.attMode = v),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => s.syncAll(scope: 'notes'),
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Синхронизировать заметки'),
            ),
          ),

          const SectionTitle('Файлы и папки на сервер'),
          FolderSyncBox(s: s),
          const SectionTitle('Пароли'),
          const Hint('Импорт и экспорт: раздел «Пароли» → кнопка ⋮ (три точки) → «Импорт» или «Экспорт». '
              'Форматы: Bitwarden JSON/CSV, KeePass XML (.xml), LastPass, 1Password, Chrome/Firefox CSV, универсальный CSV. '
              'Файл .kdbx зашифрован: в KeePass выберите «Файл → Экспорт → KeePass XML».'),
      ];
}
