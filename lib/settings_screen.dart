import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'autofill.dart';
import 'family.dart';
import 'google.dart';
import 'local_tx.dart';
import 'models.dart';
import 'store.dart';
import 'sync.dart';
import 'util.dart';
import 'widgets.dart';

const List<int> kProfileColors = [
  0xFF007AFF, 0xFFFF3B30, 0xFFFF9500, 0xFF34C759, 0xFF5856D6, 0xFFAF52DE, 0xFF00C7BE,
];

class SettingsScreen extends StatefulWidget {
  final Store store;
  final void Function(String theme) onTheme;
  const SettingsScreen({super.key, required this.store, required this.onTheme});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Map<String, TextEditingController> c;
  late Settings st;
  bool bioAvail = false;
  String gStatus = '';

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    st = s.settings;
    c = {
      'author': TextEditingController(text: st.author),
      'url': TextEditingController(text: st.url),
      'user': TextEditingController(text: st.user),
      'pass': TextEditingController(text: st.pass),
      'family': TextEditingController(text: st.familyPass),
      'txUrl': TextEditingController(text: st.txUrl),
      'txKey': TextEditingController(text: st.txKey),
      'txModel': TextEditingController(text: st.txModel),
      'gId': TextEditingController(text: st.gClientId),
      'gSecret': TextEditingController(text: st.gSecret),
      'lock': TextEditingController(text: st.autoLock.toString()),
    };
    s.bioAvailable().then((v) {
      if (mounted) setState(() => bioAvail = v);
    });
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _apply() {
    st.author = c['author']!.text.trim();
    st.url = c['url']!.text.trim();
    st.user = c['user']!.text.trim();
    st.pass = c['pass']!.text;
    st.familyPass = c['family']!.text;
    st.txUrl = c['txUrl']!.text.trim();
    st.txKey = c['txKey']!.text.trim();
    st.txModel = c['txModel']!.text.trim();
    st.gClientId = c['gId']!.text.trim();
    st.gSecret = c['gSecret']!.text.trim();
    final l = int.tryParse(c['lock']!.text.trim()) ?? 90;
    st.autoLock = l.clamp(15, 3600).toInt();
  }

  Future<void> _save({bool sync = false}) async {
    _apply();
    await s.saveSettings();
    if (!mounted) return;
    s.refresh();
    if (sync) {
      s.syncAll();
      toast(context, 'Синхронизация запущена');
    } else {
      toast(context, 'Сохранено');
    }
  }

  Widget _field(String key, String label,
      {bool obscure = false, String? hint, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c[key],
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _drop(String label, String value, Map<String, String> opts,
      void Function(String) set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(child: Text(label)),
        DropdownButton<String>(
          value: opts.containsKey(value) ? value : opts.keys.first,
          items: [
            for (final o in opts.entries)
              DropdownMenuItem(value: o.key, child: Text(o.value)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => set(v));
          },
        ),
      ]),
    );
  }

  Future<void> _members() async {
    _apply();
    try {
      final list = await SyncService.members(s);
      final granted = await FamilyKeys.granted(s);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Участники'),
          content: SizedBox(
            width: 340,
            child: ListView(shrinkWrap: true, children: [
              for (final m in list)
                Builder(builder: (_) {
                  final uuid = (m['uuid'] ?? '').toString();
                  final pub = (m['pub'] ?? '').toString();
                  final has = granted.contains(uuid);
                  Widget? trailing;
                  if (has) {
                    trailing = Icon(Icons.check_circle,
                        color: Pal.success(ctx), size: 20);
                  } else if (st.famKey.isNotEmpty && pub.isNotEmpty) {
                    trailing = TextButton(
                      onPressed: () async {
                        try {
                          await FamilyKeys.grant(s, uuid, pub);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) toast(context, 'Доступ выдан');
                        } catch (e) {
                          if (mounted) toast(context, '$e');
                        }
                      },
                      child: const Text('Дать доступ'),
                    );
                  }
                  return ListTile(
                    leading: Avatar((m['name'] ?? '?').toString(),
                        ((m['color'] ?? 0xFF007AFF) as num).toInt()),
                    title: Text((m['name'] ?? '').toString()),
                    subtitle: Text(
                        has
                            ? 'Есть доступ к семейным заметкам'
                            : (pub.isEmpty
                                ? 'Ещё не обновил приложение'
                                : 'Ждёт доступа'),
                        style: const TextStyle(fontSize: 12)),
                    trailing: trailing,
                  );
                }),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _google() async {
    _apply();
    setState(() => gStatus = 'Откроется браузер для входа в Google…');
    try {
      await GoogleCal.authorize(s);
      setState(() => gStatus = 'Подключено');
      s.syncAll();
    } catch (e) {
      setState(() => gStatus = '$e');
    }
  }

  Future<void> _bio(bool on) async {
    if (on) {
      final ok = await s.enableBiometric();
      if (!ok && mounted) toast(context, 'Не удалось включить биометрию');
    } else {
      await s.disableBiometric();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle('Профиль'),
          _field('author', 'Ваше имя', hint: 'Папа'),
          Wrap(spacing: 10, children: [
            for (final col in kProfileColors)
              GestureDetector(
                onTap: () => setState(() => st.color = col),
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
          _drop('Вложения (фото, голос, файлы)', st.attMode,
              const {'wifi': 'Только Wi-Fi', 'any': 'Любая сеть', 'off': 'Не синхронизировать'},
              (v) => st.attMode = v),

          const SectionTitle('Семья'),
          Hint(st.famKey.isEmpty
              ? 'Один человек создаёт семейный ключ. Остальные входят в приложение, настраивают '
                  'WebDAV и нажимают «Сохранить и синхронизировать» — их профиль появится в списке участников, '
                  'где владелец ключа нажимает «Дать доступ». Ключ приходит при следующей синхронизации. '
                  'Все участники должны работать с одной папкой MySecureApp в Облаке.'
              : 'Семейный ключ на этом устройстве есть. Новым участникам доступ выдаётся в списке участников.'),
          if (st.famKey.isEmpty && st.familyPass.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton(
                onPressed: !st.syncConfigured
                    ? null
                    : () async {
                        _apply();
                        try {
                          await FamilyKeys.createFamily(s);
                          if (mounted) {
                            setState(() {});
                            toast(context, 'Семейный ключ создан');
                          }
                          s.syncAll();
                        } catch (e) {
                          if (mounted) toast(context, '$e');
                        }
                      },
                child: const Text('Создать семейный ключ'),
              ),
            ),
          OutlinedButton(
              onPressed: st.syncConfigured ? _members : null,
              child: const Text('Участники')),
          const SizedBox(height: 12),
          const Hint('Запасной вариант без ключей: общий семейный пароль (одинаковый у всех). '
              'Не используйте его вместе с семейным ключом.'),
          _field('family', 'Семейный пароль', obscure: true),

          const SectionTitle('Фото'),
          _drop('Качество при добавлении', st.photoQuality, const {
            'ask': 'Спрашивать',
            'high': 'Высокое',
            'mid': 'Среднее',
            'low': 'Низкое',
            'orig': 'Исходное',
          }, (v) => st.photoQuality = v),

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
          _drop('Язык', st.txLang,
              const {'auto': 'Авто', 'ru': 'Русский', 'en': 'Английский'},
              (v) => st.txLang = v),
          _field('txUrl', 'Адрес API'),
          _field('txKey', 'API-ключ', obscure: true),
          _field('txModel', 'Модель'),

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
          ]),
          if (gStatus.isNotEmpty) Hint(gStatus),

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

          const SizedBox(height: 20),
          FilledButton(
              onPressed: () => _save(sync: true),
              child: const Text('Сохранить и синхронизировать')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: () => _save(), child: const Text('Только сохранить')),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: s,
            builder: (context, _) => Text(s.status,
                style: TextStyle(color: Pal.secondary(context), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Мастер разрешений Android: батарея, автозапуск, инструкции по брендам.
Future<void> showPermissionWizard(BuildContext context, Store s) async {
  if (!Platform.isAndroid) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Надёжные напоминания'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('1. Отключите оптимизацию батареи для приложения.'),
          TextButton(
            onPressed: () => const AndroidIntent(
                    action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS')
                .launch(),
            child: const Text('Открыть настройки батареи'),
          ),
          const Text('2. Разрешите автозапуск и работу в фоне.'),
          TextButton(
            onPressed: () => const AndroidIntent(
                    action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
                    data: 'package:com.mysecure.mysecure_notes')
                .launch(),
            child: const Text('Открыть настройки приложения'),
          ),
          const SizedBox(height: 8),
          const Text('Где искать:', style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('• Xiaomi / Redmi / Poco: Безопасность → Разрешения → Автозапуск; '
              'в «Экономии заряда» выберите «Нет ограничений».\n'
              '• Huawei / Honor: Батарея → Запуск приложений → отключите «Автоматическое управление», '
              'включите все три переключателя.\n'
              '• Motorola (китайская прошивка): Настройки → Батарея → Оптимизация → «Не оптимизировать»; '
              'закрепите приложение в списке недавних (замок).\n'
              '• Остальные: Приложения → Батарея → «Без ограничений».'),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            s.settings.wizardDone = true;
            s.saveSettings();
            Navigator.pop(ctx);
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}
