import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Транскрипция через облачный Whisper-совместимый API (OpenAI, Groq и др.).
/// Локальная модель Whisper требует нативной библиотеки и в эту сборку не входит.
class Transcriber {
  static Future<String> run(Settings s, Uint8List audio, String filename) async {
    if (s.txKey.isEmpty) throw 'Не указан API-ключ (Настройки → Голос)';
    final req = http.MultipartRequest('POST', Uri.parse(s.txUrl));
    req.headers['Authorization'] = 'Bearer ${s.txKey}';
    req.fields['model'] = s.txModel;
    if (s.txLang != 'auto') req.fields['language'] = s.txLang;
    req.files.add(http.MultipartFile.fromBytes('file', audio, filename: filename));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) {
      throw 'Ошибка API ${r.statusCode}: ${utf8.decode(r.bodyBytes, allowMalformed: true)}';
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['text'] ?? '') as String).trim();
  }
}
