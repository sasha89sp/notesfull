/// Заглушка системных функций Windows (глобальные клавиши и переназначение).
/// В Windows-сборке этот файл заменяется на variants/win32/winsys.dart (пакет win32).
class WinSys {
  static const bool available = false;

  /// Нажата ли клавиша прямо сейчас (виртуальный код VK), в том числе вне окна приложения.
  static bool isDown(int vk) => false;

  /// Включить переназначение: каждое правило — [откуда, куда1, куда2, …] (коды VK).
  /// Возвращает текст ошибки или null.
  static Future<String?> startRemap(List<List<int>> rules) async =>
      'Недоступно в этой сборке (нужна Windows-сборка с win32)';

  static void stopRemap() {}
}
