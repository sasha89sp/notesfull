/// Заглушка локальной расшифровки. В сборке «whisper» этот файл заменяется
/// на variants/whisper/local_tx.dart (пакет whisper_ggml).
class LocalTx {
  static const bool available = false;

  static Future<String> transcribe(
      String wavPath, String model, String lang) async {
    throw 'Локальная расшифровка есть только в сборке «whisper»';
  }
}
