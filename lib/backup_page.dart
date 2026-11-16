// ▸ Экран «Бэкап»: приложение и настройки / телефон (кнопка +, восстановление архива телефона)
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'crypto.dart';
import 'models.dart';
import 'phone_data.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

part 'backup_page_2.dart';


/// Модуль «Бэкап»: полный бэкап приложения и перенос данных телефона
/// (звонки, контакты, SMS, Wi-Fi) в файл и обратно.
class BackupPage extends StatefulWidget {
  final Store store;
  const BackupPage({super.key, required this.store});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String _status = '';
  bool _encrypt = true;
  bool _toCloud = false;

  @override
  Widget build(BuildContext context) {
    final android = PhoneData.available;
    final st = s.settings;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator()),
      if (_status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_status, style: TextStyle(color: Pal.secondary(context))),
        ),

      // ======================= 1. приложение и настройки =======================
      _sectionHead('Приложение и настройки', 'Заметки, события, пароли, вложения и настройки профиля',
          Icons.apps_outlined),
      _card('Полный бэкап ASRbox', Icons.inventory_2_outlined,
          'Всё содержимое профиля одним файлом; остаётся зашифрованным вашим паролем.', [
        _btn('В файл', Icons.save_alt, _fullToFile, filled: true),
        _btn('В облако', Icons.cloud_upload_outlined, _fullToCloud),
        _btn('Облако и расписание', Icons.settings_outlined, () {
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(store: s, onTheme: (_) {}, onLogout: (_) async {})));
        }),
      ]),
      const SizedBox(height: 8),
      const Divider(),

      // ============================ 2. телефон ============================
      _sectionHead('Телефон', 'Данные устройства: звонки, контакты, SMS, Wi-Fi', Icons.smartphone_outlined),
      if (!android)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Бэкап телефона доступен только в Android-версии.'),
        )
      else ...[
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _phoneRestore,
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('Восстановить из архива телефона'),
          ),
        ),
        const SizedBox(height: 8),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.folder_special_outlined, size: 34, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Бэкап телефона',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(
                      'Одно нажатие: собираются все доступные данные и сразу загружаются в облако.'
                      '${st.bkPhoneLast > 0 ? '\nПоследний: ${fmtDate(st.bkPhoneLast)}' : ''}',
                      style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
                ]),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                heroTag: 'phoneBackup',
                onPressed: _busy ? null : _phoneAll,
                tooltip: 'Создать бэкап телефона и загрузить в облако',
                child: const Icon(Icons.add),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: const [0, 6, 24, 168].contains(st.bkPhoneEvery) ? st.bkPhoneEvery : 0,
          decoration: const InputDecoration(labelText: 'Расписание автоматического бэкапа телефона'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Выключено')),
            DropdownMenuItem(value: 6, child: Text('Каждые 6 часов')),
            DropdownMenuItem(value: 24, child: Text('Раз в сутки')),
            DropdownMenuItem(value: 168, child: Text('Раз в неделю')),
          ],
          onChanged: (v) async {
            st.bkPhoneEvery = v ?? 0;
            await s.saveSettings();
            if (mounted) setState(() {});
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
          child: Text(
              'По расписанию копия делается, пока приложение открыто (или работает в фоне), '
              'и нужны уже выданные разрешения и настроенное облако. Android не позволяет '
              'приложению просыпаться по расписанию, когда оно полностью закрыто.',
              style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Шифровать отдельные файлы ключом профиля'),
          subtitle: const Text('Файлы с данными телефона содержат личное; расшифровать их можно только в этом профиле',
              style: TextStyle(fontSize: 12)),
          value: _encrypt,
          onChanged: (v) => setState(() => _encrypt = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Отдельный экспорт тоже загружать в облако'),
          subtitle: const Text('На сервер для бэкапов (WebDAV, Яндекс Диск или Google Диск)',
              style: TextStyle(fontSize: 12)),
          value: _toCloud,
          onChanged: (v) => setState(() => _toCloud = v),
        ),
        _sectionHead('Отдельные данные', 'Экспорт и импорт по одному виду', Icons.tune),
        _card('Журнал звонков', Icons.call_outlined, 'Номера, время, длительность, тип.', [
          _btn('Экспорт', Icons.upload_file, _callsExport),
          _btn('Импорт', Icons.download, _callsImport),
        ]),
        _card('Контакты', Icons.contacts_outlined, 'vCard (.vcf) открывается в любом телефоне; JSON — для ASRbox.', [
          _btn('Экспорт vCard', Icons.upload_file, () => _contactsExport(true)),
          _btn('Экспорт JSON', Icons.upload_file, () => _contactsExport(false)),
          _btn('Импорт', Icons.download, _contactsImport),
        ]),
        _card('SMS', Icons.sms_outlined,
            'Экспорт работает всегда. Запись обратно в телефон Android разрешает только SMS-приложению по умолчанию.', [
          _btn('Экспорт', Icons.upload_file, _smsExport),
          _btn('Импорт', Icons.download, _smsImport),
        ]),
        _card('Wi-Fi', Icons.wifi,
            'Android 10+ не отдаёт пароли сохранённых сетей. Экспортируются доступные сети; пароли можно дописать в файл или добавить вручную. '
            'При импорте сети предлагаются системе и подтверждаются пользователем.', [
          _btn('Экспорт', Icons.upload_file, _wifiExport),
          _btn('Добавить сеть', Icons.add, _wifiAdd),
          _btn('Импорт', Icons.download, _wifiImport),
        ]),
      ],
    ]);
  }}