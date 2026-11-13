import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'applog.dart';
import 'autofill.dart';
import 'backup.dart';
import 'diag_screens.dart';
import 'family.dart';
import 'google.dart';
import 'ics.dart';
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
  final Future<void> Function(bool picker) onLogout;
  const SettingsScreen(
      {super.key,
      required this.store,
      required this.onTheme,
      required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Map<String, TextEditingController> c;
  late Settings st;
  bool bioAvail = false;
  String gStatus = '';
  Timer? _autoTimer;
  String _syncSig = '';

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
      'gUrl': TextEditingController(text: st.grpUrl),
      'gUser': TextEditingController(text: st.grpUser),
      'gPass': TextEditingController(text: st.grpPass),
      'gFolder': TextEditingController(text: st.grpFolder),
    };
    _syncSig = '${st.url}|${st.user}|${st.pass}';
    s.bioAvailable().then((v) {
      if (mounted) setState(() => bioAvail = v);
    });
  }

  @override
  void dispose() {
    // несохранённые правки записываем сразу
    if (_autoTimer?.isActive ?? false) {
      _autoTimer!.cancel();
      _autoNow();
    }
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
    st.grpUrl = c['gUrl']!.text.trim();
    st.grpUser = c['gUser']!.text.trim();
    st.grpPass = c['gPass']!.text;
    st.grpFolder = c['gFolder']!.text.trim();
    final l = int.tryParse(c['lock']!.text.trim()) ?? 90;
    st.autoLock = l.clamp(15, 3600).toInt();
  }

  /// Настройки сохраняются сами, кнопка «Сохранить» не нужна.
  void _auto() {
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(milliseconds: 700), _autoNow);
  }

  Future<void> _autoNow() async {
    final oldName = st.author;
    _apply();
    await s.saveSettings();
    if (st.author != oldName) await s.renameCurrent(st.author);
    final sig = '${st.url}|${st.user}|${st.pass}';
    final changed = sig != _syncSig;
    _syncSig = sig;
    s.refresh();
    // ввели или изменили данные WebDAV: синхронизация запускается автоматически
    if (changed && st.syncConfigured) s.syncAll();
  }

  Widget _field(String key, String label,
      {bool obscure = false, String? hint, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c[key],
        obscureText: obscure,
        keyboardType: type,
        onChanged: (_) => _auto(),
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
            if (v != null) {
              setState(() => set(v));
              _auto();
            }
          },
        ),
      ]),
    );
  }

  Future<void> _copyInvite() async {
    _apply();
    final j = jsonEncode({
      'v': 1,
      'u': st.grpUrl,
      'n': st.grpUser,
      'p': st.grpPass,
      'f': st.grpFolder,
    });
    await Clipboard.setData(ClipboardData(text: 'asrbox:${base64Url.encode(utf8.encode(j))}'));
    if (mounted) toast(context, 'Приглашение скопировано');
  }

  Future<void> _pasteInvite() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (d?.text ?? '').trim();
    try {
      if (!t.startsWith('asrbox:')) throw 'нет приглашения в буфере обмена';
      final m = jsonDecode(utf8.decode(base64Url.decode(t.substring(7)))) as Map;
      setState(() {
        c['gUrl']!.text = (m['u'] ?? '') as String;
        c['gUser']!.text = (m['n'] ?? '') as String;
        c['gPass']!.text = (m['p'] ?? '') as String;
        c['gFolder']!.text = (m['f'] ?? '') as String;
      });
      _autoNow();
      if (mounted) toast(context, 'Группа подключена');
    } catch (e) {
      if (mounted) toast(context, 'Приглашение не распознано: $e');
    }
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
      if (mounted) setState(() => gStatus = 'Подключено');
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

  Future<bool> _ask(String title, String text, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _davLogout() async {
    if (!await _ask('Выйти из WebDAV?',
        'Приложение отключится от облака. Локальные данные останутся на устройстве.', 'Выйти')) {
      return;
    }
    s.cancelSync();
    st.user = '';
    st.pass = '';
    c['user']!.text = '';
    c['pass']!.text = '';
    _syncSig = '${st.url}||';
    await s.saveSettings();
    s.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _googleLogout() async {
    if (!await _ask('Выйти из Google Календаря?',
        'Аккаунт будет отключён. Локальные события останутся.', 'Выйти')) {
      return;
    }
    await GoogleCal.disconnect(s);
    if (mounted) setState(() => gStatus = 'Отключено');
  }

  Future<void> _backup() async {
    try {
      final bytes = await Backup.create(s);
      final d = DateTime.now();
      final name = 'mysecure_backup_${d.year}${two(d.month)}${two(d.day)}.zip';
      if (await saveBytes(name, bytes) && mounted) toast(context, 'Бэкап сохранён');
    } catch (e, stk) {
      AppLog.I.e('backup', '$e', stk);
      if (mounted) toast(context, 'Ошибка бэкапа: $e');
    }
  }

  Future<void> _restore() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final bytes = r.files.first.bytes!;
    if (!Backup.isBackup(bytes)) {
      if (mounted) toast(context, 'Это не бэкап приложения');
      return;
    }
    if (!mounted) return;
    if (!await _ask('Восстановить из бэкапа?',
        'Данные текущего профиля будут заменены. После восстановления войдите с паролем, '
            'под которым делался бэкап.',
        'Восстановить')) {
      return;
    }
    try {
      await Backup.restore(s, bytes);
      await widget.onLogout(false);
    } catch (e, stk) {
      AppLog.I.e('backup', '$e', stk);
      if (mounted) toast(context, 'Ошибка восстановления: $e');
    }
  }

  Future<void> _jexImport() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['jex'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    try {
      final msg = await Jex.importInto(s, r.files.first.bytes!);
      if (mounted) toast(context, 'Импорт Joplin: $msg');
    } catch (e, stk) {
      AppLog.I.e('jex', '$e', stk);
      if (mounted) toast(context, 'Не удалось прочитать JEX: $e');
    }
  }

  Future<void> _jexExport() async {
    try {
      final bytes = await Jex.exportFrom(s);
      if (await saveBytes('mysecure_notes.jex', bytes) && mounted) {
        toast(context, 'JEX сохранён');
      }
    } catch (e, stk) {
      AppLog.I.e('jex', '$e', stk);
      if (mounted) toast(context, 'Ошибка экспорта: $e');
    }
  }

  Future<void> _icsImport() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['ics'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final list = Ics.import(utf8.decode(r.files.first.bytes!, allowMalformed: true));
    final have = {
      for (final e in s.events)
        if (!e.deleted) '${e.title}|${e.start}|${e.end}'
    };
    final fresh = list.where((e) => have.add('${e.title}|${e.start}|${e.end}')).toList();
    s.events.addAll(fresh);
    s.eventsChanged();
    if (mounted) {
      toast(context, 'Импортировано событий: ${fresh.length}'
          '${list.length > fresh.length ? ' (повторы пропущены: ${list.length - fresh.length})' : ''}');
    }
  }

  Future<void> _icsExport() async {
    if (await saveBytes('calendar.ics', utf8.encode(Ics.export(s.events))) && mounted) {
      toast(context, 'Файл сохранён');
    }
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

          const SectionTitle('Модули'),
          const Hint('Отключённый модуль не загружается и не нагружает приложение. '
              'Связи работают и при отключённом модуле: например, событие, созданное '
              'из заметки, попадёт в календарь и напомнит о себе.'),
          for (final m in const {
            'notes': 'Заметки',
            'calendar': 'Календарь',
            'pass': 'Пароли',
            'chat': 'Чаты',
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

          const SectionTitle('Общая группа (другой WebDAV)'),
          const Hint('Чтобы объединить в семью людей, которые входят через разные WebDAV, '
              'укажите один общий WebDAV для группы: общие заметки, комментарии и чат '
              'будут лежать там. Личные данные остаются на вашем хранилище. '
              'Оставьте пустым, если все используют одно хранилище.'),
          _field('gUrl', 'Адрес WebDAV группы'),
          _field('gUser', 'Логин WebDAV группы'),
          _field('gPass', 'Пароль WebDAV группы', obscure: true),
          _field('gFolder', 'Папка группы'),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: st.groupConfigured ? _copyInvite : null,
                child: const Text('Копировать приглашение'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _pasteInvite,
                child: const Text('Вставить приглашение'),
              ),
            ),
          ]),
          const Hint('Приглашение содержит доступ к WebDAV группы — передавайте только '
              'тем, кому доверяете. Семейный ключ выдаётся отдельно, в «Участники».'),

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
            const Spacer(),
            if (st.googleConfigured)
              OutlinedButton(
                  onPressed: _googleLogout,
                  child: const Text('Выйти из Google Календаря')),
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

          const SectionTitle('История синхронизации'),
          const Hint('Дата, статус, сколько данных отправлено и получено, куда и подробный журнал.'),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SyncHistoryScreen(store: s))),
            child: const Text('Открыть историю'),
          ),

          const SectionTitle('Резервная копия и перенос'),
          const Hint('Бэкап содержит все данные профиля, включая пароли и вложения, в зашифрованном виде. '
              'Joplin: заметки, папки, теги и вложения (формат JEX). Календарь: файлы .ics.'),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton(onPressed: _backup, child: const Text('Полный бэкап')),
            OutlinedButton(onPressed: _restore, child: const Text('Восстановить')),
            OutlinedButton(onPressed: _jexImport, child: const Text('Импорт из Joplin')),
            OutlinedButton(onPressed: _jexExport, child: const Text('Экспорт в Joplin')),
            OutlinedButton(onPressed: _icsImport, child: const Text('Импорт календаря')),
            OutlinedButton(onPressed: _icsExport, child: const Text('Экспорт календаря')),
          ]),
          const Hint('Импорт и экспорт паролей (CSV и другие форматы) находятся во вкладке «Пароли», меню ⋮.'),

          const SectionTitle('Отладка и диагностика'),
          const Hint('Журнал ошибок, сбоев и зависаний с причинами; его можно сохранить файлом.'),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => LogScreen(store: s))),
            child: const Text('Открыть журнал'),
          ),
          const SizedBox(height: 8),
          const Hint('Все изменения в настройках сохраняются автоматически.'),
          const SizedBox(height: 8),
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
