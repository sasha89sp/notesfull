part of 'settings_screen.dart';

extension _ExtSettingsWidgetsA on _SettingsScreenState {
  List<Widget> _allWidgets() => [
        ..._widgetsA(),
        ..._widgetsB(),
        ..._widgetsC(),
        ..._widgetsD(),
      ];

  List<Widget> _widgetsA() => [
          const SectionTitle('Профиль'),
          _field('author', 'Ваше имя', hint: 'Папа'),
          Wrap(spacing: 10, children: [
            for (final col in kProfileColors)
              GestureDetector(
                onTap: () {
                  setState(() => st.color = col);
                  _auto();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(col),
                    shape: BoxShape.circle,
                    border: st.color == col
                        ? Border.all(width: 3, color: Pal.secondary(context))
                        : null,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Hint('Идентификатор профиля: ${st.profileId}'),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  if (await _ask('Выйти из профиля?',
                      'Данные останутся на устройстве. Для входа понадобится пароль.', 'Выйти')) {
                    await widget.onLogout(false);
                  }
                },
                child: const Text('Выйти из профиля'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => widget.onLogout(true),
                child: const Text('Сменить профиль'),
              ),
            ),
          ]),
          if (BgSync.available)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Фоновая синхронизация'),
              subtitle: const Text(
                  'Раз в ~30 минут, даже когда приложение закрыто. Нужен вход по биометрии '
                  '(ключ хранится в защищённом хранилище телефона). На Motorola и других '
                  'китайских прошивках разрешите автозапуск и снимите ограничение батареи.',
                  style: TextStyle(fontSize: 12)),
              value: st.bgSync,
              onChanged: (v) async {
                if (v && !await s.bioStored()) {
                  if (mounted) toast(context, 'Сначала включите вход по биометрии (Шифрование)');
                  return;
                }
                setState(() => st.bgSync = v);
                await BgSync.apply(v);
                s.refresh();
                _auto();
              },
            ),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
          _drop('Вид интерфейса', st.uiMode,
              const {'auto': 'Авто (по устройству)', 'desktop': 'Компьютер (три блока, мышь)', 'mobile': 'Телефон'},
              (v) {
            st.uiMode = v;
            s.refresh();
            _auto();
          }),
          if (st.uiMode != 'mobile')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    st.paneOrder = ['side', 'list', 'detail'];
                    st.paneW = {'side': 230, 'list': 330};
                  });
                  s.refresh();
                  _auto();
                },
                icon: const Icon(Icons.view_column_outlined, size: 18),
                label: const Text('Сбросить расположение блоков'),
              ),
            ),
          ],
          Row(children: [
            Text('Размер интерфейса ${(st.fontScale * 100).round()}%'),
            Expanded(
              child: Slider(
                min: 0.8,
                max: 1.6,
                divisions: 16,
                label: '${(st.fontScale * 100).round()}%',
                value: st.fontScale.clamp(0.8, 1.6).toDouble(),
                onChanged: (v) {
                  setState(() => st.fontScale = double.parse(v.toStringAsFixed(2)));
                  s.refresh();
                  _auto();
                },
              ),
            ),
            IconButton(
              tooltip: 'Сбросить до 100%',
              icon: const Icon(Icons.restart_alt, size: 20),
              onPressed: st.fontScale == 1.0
                  ? null
                  : () {
                      setState(() => st.fontScale = 1.0);
                      s.refresh();
                      _auto();
                    },
            ),
          ]),
          _drop('Строка статуса синхронизации', st.stripPos,
              const {
                'bottom': 'Снизу',
                'top': 'Сверху',
                'sync': 'Снизу, только во время синхронизации',
                'off': 'Скрыта',
              },
              (v) {
            st.stripPos = v;
            s.refresh();
            _auto();
          }),
          _drop('Нижнее меню (телефон)', st.navMode,
              const {
                'show': 'Всегда показывать',
                'auto': 'Прятать при прокрутке вниз',
                'hide': 'Убрать (разделы — в боковом меню)',
              },
              (v) {
            st.navMode = v;
            _navFix();
          }),
          _drop('Тема', st.theme,
              const {'system': 'Системная', 'light': 'Светлая', 'dark': 'Тёмная'},
              (v) {
            st.theme = v;
            widget.onTheme(v);
          }),

          const SectionTitle('Синхронизация WebDAV'),
          const Hint(
              'Mail.ru Облако: адрес https://webdav.cloud.mail.ru, логин — ваша почта, '
              'пароль — «пароль для внешнего приложения» (настройки безопасности Mail.ru, доступ WebDAV).'),
          _field('url', 'Адрес WebDAV'),
          _field('user', 'Логин'),
          _field('pass', 'Пароль приложения', obscure: true),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: st.syncConfigured ? _davLogout : null,
                child: const Text('Выйти из WebDAV'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedBuilder(
                animation: s,
                builder: (context, _) => OutlinedButton(
                  onPressed: s.syncing ? s.cancelSync : null,
                  child: const Text('Отмена'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _drop('Вложения (фото, голос, файлы)', st.attMode,
              const {'wifi': 'Только Wi-Fi', 'any': 'Любая сеть', 'off': 'Не синхронизировать'},
              (v) => st.attMode = v),

          const SectionTitle('Когда синхронизировать'),
          const Hint('Чтобы приложение не делало лишних обращений к серверу и не подвисало. '
              'Кнопкой синхронизации можно запустить обмен в любой момент.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('При запуске приложения'),
            value: st.syncOnStart,
            onChanged: (v) => setState(() {
              st.syncOnStart = v;
              _auto();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('После правок'),
            subtitle: const Text('Через 5 секунд после изменения заметки, события или пароля',
                style: TextStyle(fontSize: 12)),
            value: st.syncOnChange,
            onChanged: (v) => setState(() {
              st.syncOnChange = v;
              _auto();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('При возврате в приложение'),
            value: st.syncOnResume,
            onChanged: (v) => setState(() {
              st.syncOnResume = v;
              _auto();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('При появлении сети'),
            value: st.syncOnNet,
            onChanged: (v) => setState(() {
              st.syncOnNet = v;
              _auto();
            }),
          ),
          _drop('Периодически', '${st.syncEvery}',
              const {'0': 'Выключено', '15': 'Каждые 15 минут', '30': 'Каждые 30 минут', '60': 'Каждый час', '180': 'Каждые 3 часа'},
              (v) {
            st.syncEvery = int.tryParse(v) ?? 0;
            _auto();
          }),
          _drop('Google Календарь', '${st.gcalEvery}',
              const {'0': 'Только вручную', '30': 'Каждые 30 минут', '60': 'Каждый час', '120': 'Каждые 2 часа', '360': 'Каждые 6 часов'},
              (v) {
            st.gcalEvery = int.tryParse(v) ?? 0;
            _auto();
          }),
          const Hint('Google Календарь загружается целиком, поэтому по расписанию он обновляется редко; '
              'после правки события в приложении он обновится сразу. '
              'Если ничего не изменилось, файлы на устройстве не перезаписываются.'),

      ];
}
