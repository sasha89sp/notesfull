import 'package:whisper_ggml/whisper_ggml.dart';

/// Локальная расшифровка через whisper.cpp (пакет whisper_ggml).
/// Модель скачивается при первом использовании и кэшируется.
class LocalTx {
  static const bool available = true;

  static Future<String> transcribe(
      String wavPath, String model, String lang) async {
    final WhisperModel m;
    switch (model) {
      case 'tiny':
        m = WhisperModel.tiny;
        break;
      case 'small':
        m = WhisperModel.small;
        break;
      default:
        m = WhisperModel.base;
    }
    final controller = WhisperController();
    final result = await controller.transcribe(
      model: m,
      audioPath: wavPath,
      lang: lang,
    );
    return (result?.transcription.text ?? '').trim();
  }
}
