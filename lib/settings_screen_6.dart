// ▸ Часть settings_screen.dart: Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт)
part of 'settings_screen.dart';


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