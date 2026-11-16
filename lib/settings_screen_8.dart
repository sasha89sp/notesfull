// ▸ Часть settings_screen.dart: Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт)  [содержит: _ExtSettingsWidgetsC]
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
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton(onPressed: _google, child: const Text('Войти в Google')),
            if (st.googleConfigured)
              Text('подключено', style: TextStyle(color: Pal.success(context))),
            if (st.googleConfigured)
              OutlinedButton(
                  onPressed: _googleLogout,
                  child: const Text('Выйти из Google Календаря')),
          ]),
          if (gStatus.isNotEmpty) Hint(gStatus),

          const SectionTitle('Синхронизация календаря'),
          const Hint('События обмениваются с сервером, Google Календарём и подписками iCal. '
              'Здесь — правила только для календаря; общие правила — в разделе «Синхронизация и бэкап».'),
          _drop('Google Календарь', '${st.gcalEvery}',
              const {'0': 'Только вручную', '30': 'Каждые 30 минут', '60': 'Каждый час', '120': 'Каждые 2 часа', '360': 'Каждые 6 часов'},
              (v) {
            st.gcalEvery = int.tryParse(v) ?? 0;
            _auto();
          }),
          const Hint('Google Календарь загружается целиком, поэтому по расписанию он обновляется редко; '
              'после правки события в приложении он обновится сразу. '
              'Если ничего не изменилось, файлы на устройстве не перезаписываются.'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => s.syncAll(scope: 'calendar'),
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Синхронизировать календарь'),
            ),
          ),

      ];
}
