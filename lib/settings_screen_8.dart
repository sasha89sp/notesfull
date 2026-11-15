part of 'settings_screen.dart';

extension _ExtSettingsWidgetsC on _SettingsScreenState {
  List<Widget> _widgetsC() => [
          const SectionTitle('Портативный режим'),
          Hint(Platform.isWindows
              ? 'Данные (заметки, настройки, журнал) хранятся в папке «data» рядом с программой, '
                  'а не в профиле Windows: программу можно носить на флешке. Состояние: '
                  '${AppDirs.portable ? 'включён' : 'выключен'}. Изменение применяется после перезапуска.'
              : 'Портативный режим есть только в Windows.'),
          if (Platform.isWindows)
            OutlinedButton(
              onPressed: () async {
                final msg = AppDirs.portable ? await AppDirs.disablePortable() : await AppDirs.enablePortable();
                if (mounted) {
                  toast(context, msg);
                  setState(() {});
                }
              },
              child: Text(AppDirs.portable ? 'Выключить портативный режим' : 'Включить портативный режим'),
            ),
          const SectionTitle('Голос'),
          Hint(LocalTx.available
              ? 'Локальная расшифровка работает без интернета: модель Whisper скачивается один раз при '
                  'первом использовании. Облачный API — запасной вариант.'
              : 'В этой сборке нет локальной модели Whisper (она есть в сборке «whisper»). '
                  'Работает облачный Whisper-совместимый API (OpenAI, Groq и др.).'),
          _drop('Расшифровка', st.txMode, {
            'ask': 'Спрашивать',
            if (LocalTx.available) 'local': 'Локально (Whisper)',
            'api': 'Всегда через API',
            'off': 'Выключена',
          }, (v) => st.txMode = v),
          if (LocalTx.available)
            _drop('Модель Whisper', st.txLocalModel, const {
              'tiny': 'Tiny (≈75 МБ, быстро)',
              'base': 'Base (≈140 МБ)',
              'small': 'Small (≈460 МБ, точнее)',
            }, (v) => st.txLocalModel = v),
          if (LocalTx.available) ModelBox(st: st, onChanged: _auto),
          _drop('Язык', st.txLang,
              const {'auto': 'Авто', 'ru': 'Русский', 'en': 'Английский'},
              (v) => st.txLang = v),
          _field('txUrl', 'Адрес API'),
          _field('txKey', 'API-ключ', obscure: true),
          _field('txModel', 'Модель'),

          const SectionTitle('Календари'),
          CalendarsBox(s: s),
          const SectionTitle('Google Календарь'),
          const Hint(
              'Создайте в Google Cloud проект, включите Calendar API и OAuth-клиент типа «Desktop app». '
              'Вставьте Client ID и Secret. Вход выполняется через браузер, сервисы Google Play не нужны.'),
          _field('gId', 'Client ID'),
          _field('gSecret', 'Client Secret', obscure: true),
          Row(children: [
            FilledButton(onPressed: _google, child: const Text('Войти в Google')),
            const SizedBox(width: 12),
            if (st.googleConfigured)
              Text('подключено', style: TextStyle(color: Pal.success(context))),
            const Spacer(),
            if (st.googleConfigured)
              OutlinedButton(
                  onPressed: _googleLogout,
                  child: const Text('Выйти из Google Календаря')),
          ]),
          if (gStatus.isNotEmpty) Hint(gStatus),

      ];
}
