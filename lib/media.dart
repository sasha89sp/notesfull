import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'local_tx.dart';
import 'models.dart';
import 'store.dart';
import 'transcribe.dart';
import 'util.dart';
import 'widgets.dart';

String humanSize(int b) {
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
}

// ------------------------------------------------------------------ фото

Uint8List _compress(Map<String, dynamic> a) {
  final bytes = a['b'] as Uint8List;
  final maxSide = a['m'] as int;
  final q = a['q'] as int;
  final im = img.decodeImage(bytes);
  if (im == null) return bytes; // HEIC и прочее — оставляем как есть
  var out = im;
  if (im.width > maxSide || im.height > maxSide) {
    out = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: q));
}

Future<String?> _askQuality(BuildContext c, Store s) async {
  var remember = false;
  final res = await showDialog<String>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Качество фото'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in const [
              ['high', 'Высокое (≈1,8 МБ) — рекомендуется'],
              ['mid', 'Среднее (≈800 КБ)'],
              ['low', 'Низкое (≈300 КБ)'],
              ['orig', 'Исходное'],
            ])
              ListTile(
                dense: true,
                title: Text(o[1]),
                onTap: () {
                  if (remember) {
                    s.settings.photoQuality = o[0];
                    s.saveSettings();
                  }
                  Navigator.pop(ctx, o[0]);
                },
              ),
            CheckboxListTile(
              dense: true,
              value: remember,
              onChanged: (v) => set(() => remember = v ?? false),
              title: const Text('Запомнить выбор'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    ),
  );
  return res;
}

Future<Block?> pickImageBlock(BuildContext c, Store s) async {
  Uint8List? bytes;
  String name = 'photo.jpg';
  if (Platform.isAndroid || Platform.isIOS) {
    final src = await showModalBottomSheet<ImageSource>(
      context: c,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Камера'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Галерея'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return null;
    final x = await ImagePicker().pickImage(source: src);
    if (x == null) return null;
    bytes = await x.readAsBytes();
    name = x.name;
  } else {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'webp', 'bmp', 'gif'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    bytes = r.files.first.bytes;
    name = r.files.first.name;
  }
  if (bytes == null) return null;
  if (!c.mounted) return null;

  var q = s.settings.photoQuality;
  if (q == 'ask') {
    q = await _askQuality(c, s) ?? '';
    if (q.isEmpty) return null;
  }
  Uint8List out = bytes;
  if (q != 'orig') {
    final params = {
      'high': [2560, 85],
      'mid': [1600, 70],
      'low': [1024, 55],
    }[q]!;
    out = await compute(_compress, {'b': bytes, 'm': params[0], 'q': params[1]});
    if (out.length > bytes.length) out = bytes;
  }
  final id = await s.addAttachment(out);
  return Block(type: 'image', meta: {'att': id, 'name': name, 'size': out.length});
}

// ------------------------------------------------------------------ файлы

const _docExt = {'pdf', 'docx', 'xlsx', 'pptx', 'txt', 'rtf', 'doc', 'xls', 'ppt', 'odt', 'ods', 'csv'};
const _arcExt = {'zip', 'rar', '7z'};
const _audExt = {'mp3', 'wav', 'm4a'};
const _vidExt = {'mp4', 'mov'};

Future<Block?> pickFileBlock(BuildContext c, Store s) async {
  final r = await FilePicker.platform.pickFiles(withData: true);
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  final bytes = f.bytes;
  if (bytes == null) return null;
  final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
  int limit;
  if (_docExt.contains(ext)) {
    limit = 50;
  } else if (_arcExt.contains(ext)) {
    limit = 100;
  } else if (_audExt.contains(ext)) {
    limit = 50;
  } else if (_vidExt.contains(ext)) {
    limit = 200;
  } else {
    if (c.mounted) {
      toast(c, 'Формат .$ext не поддерживается. Допустимы документы, архивы, аудио и видео.');
    }
    return null;
  }
  if (bytes.length > limit * 1024 * 1024) {
    if (c.mounted) toast(c, 'Файл больше $limit МБ');
    return null;
  }
  final id = await s.addAttachment(bytes);
  return Block(type: 'file', meta: {'att': id, 'name': f.name, 'size': bytes.length});
}

// ------------------------------------------------------------------ виджеты блоков

class ImageBlockView extends StatefulWidget {
  final Store store;
  final Block block;
  const ImageBlockView({super.key, required this.store, required this.block});
  @override
  State<ImageBlockView> createState() => _ImageBlockViewState();
}

class _ImageBlockViewState extends State<ImageBlockView> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.block.att;
    if (id != null) _bytes = await widget.store.readAttachment(id);
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
          height: 80, child: Center(child: CircularProgressIndicator()));
    }
    if (_bytes == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Фото ещё не загружено. Оно скачается при синхронизации (по Wi-Fi).',
            style: TextStyle(color: Pal.secondary(context))),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () async {
                  final name = (widget.block.meta['name'] ?? 'photo.jpg') as String;
                  final ok = await saveBytes(name, _bytes!);
                  if (ok && context.mounted) toast(context, 'Сохранено');
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(child: Image.memory(_bytes!)),
          ),
        ),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_bytes!,
            fit: BoxFit.cover,
            height: 220,
            width: double.infinity,
            cacheWidth: 1200),
      ),
    );
  }
}

class FileBlockView extends StatelessWidget {
  final Store store;
  final Block block;
  const FileBlockView({super.key, required this.store, required this.block});

  @override
  Widget build(BuildContext context) {
    final name = (block.meta['name'] ?? 'файл') as String;
    final size = (block.meta['size'] ?? 0) as int;
    final have = block.att != null && store.hasAttachment(block.att!);
    return Row(children: [
      const Icon(Icons.attach_file),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(have ? humanSize(size) : '${humanSize(size)} · ещё не загружен',
              style: TextStyle(color: Pal.secondary(context), fontSize: 12)),
        ]),
      ),
      TextButton(
        onPressed: !have
            ? null
            : () async {
                final b = await store.readAttachment(block.att!);
                if (b == null) return;
                final ok = await saveBytes(name, b);
                if (ok && context.mounted) toast(context, 'Сохранено');
              },
        child: const Text('Сохранить'),
      ),
    ]);
  }
}

class VoiceBlockView extends StatefulWidget {
  final Store store;
  final Block block;
  final VoidCallback onChanged;
  const VoiceBlockView(
      {super.key,
      required this.store,
      required this.block,
      required this.onChanged});
  @override
  State<VoiceBlockView> createState() => _VoiceBlockViewState();
}

class _VoiceBlockViewState extends State<VoiceBlockView> {
  AudioRecorder? _rec;
  AudioPlayer? _player;
  bool _recording = false;
  bool _playing = false;
  bool _busy = false;
  final Stopwatch _sw = Stopwatch();
  Timer? _tick;
  String? _tmpPlay;
  late final TextEditingController _tx;

  Block get b => widget.block;
  String get _ext => (b.meta['ext'] ?? 'm4a') as String;

  @override
  void initState() {
    super.initState();
    _tx = TextEditingController(text: b.content);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec?.dispose();
    _player?.dispose();
    _cleanupTmp();
    _tx.dispose();
    super.dispose();
  }

  void _cleanupTmp() {
    final p = _tmpPlay;
    if (p != null) {
      try {
        File(p).deleteSync();
      } catch (_) {}
      _tmpPlay = null;
    }
  }

  Future<void> _start() async {
    try {
      _rec ??= AudioRecorder();
      if (!await _rec!.hasPermission()) {
        if (mounted) toast(context, 'Нет доступа к микрофону');
        return;
      }
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}rec_${newId()}.wav';
      // 16 кГц моно WAV: формат, который понимает Whisper без конвертации
      await _rec!.start(
        const RecordConfig(
            encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      _sw
        ..reset()
        ..start();
      _tick = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() {}));
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось начать запись: $e');
    }
  }

  Future<void> _stop() async {
    _tick?.cancel();
    _sw.stop();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final path = await _rec!.stop();
      if (path != null) {
        final f = File(path);
        final bytes = await f.readAsBytes();
        try {
          await f.delete();
        } catch (_) {}
        final id = await widget.store.addAttachment(bytes);
        b.meta['att'] = id;
        b.meta['ext'] = path.split('.').last;
        b.meta['duration'] = _sw.elapsed.inSeconds;
        b.meta['size'] = bytes.length;
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) toast(context, 'Ошибка записи: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player?.stop();
      _cleanupTmp();
      setState(() => _playing = false);
      return;
    }
    final id = b.att;
    if (id == null) return;
    final bytes = await widget.store.readAttachment(id);
    if (bytes == null) {
      if (mounted) toast(context, 'Запись ещё не загружена');
      return;
    }
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}play_${newId()}.$_ext';
    await File(path).writeAsBytes(bytes);
    _tmpPlay = path;
    _player ??= AudioPlayer();
    _player!.onPlayerComplete.listen((_) {
      _cleanupTmp();
      if (mounted) setState(() => _playing = false);
    });
    await _player!.play(DeviceFileSource(path));
    setState(() => _playing = true);
  }

  Future<void> _transcribe() async {
    final s = widget.store.settings;
    var mode = s.txMode;
    if (mode == 'off') {
      toast(context, 'Транскрипция выключена в настройках');
      return;
    }
    if (mode == 'ask') {
      final pick = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Расшифровать запись'),
          content: Text(LocalTx.available
              ? 'Локально: аудио не покидает устройство, при первом запуске скачается модель. '
                  'Через API: аудио отправляется на сервис из настроек.'
              : 'Аудио будет отправлено на сервис распознавания из настроек (Whisper API). '
                  'Локальной модели в этой сборке нет.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            if (LocalTx.available)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'local'),
                  child: const Text('Локально')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'api'),
                child: const Text('Через API')),
          ],
        ),
      );
      if (pick == null) return;
      mode = pick;
    }
    final id = b.att;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.store.readAttachment(id);
      if (bytes == null) throw 'Запись не загружена';
      String text;
      if (mode == 'local') {
        if (!LocalTx.available) {
          throw 'Локальная расшифровка есть только в сборке «whisper»';
        }
        final path =
            '${Directory.systemTemp.path}${Platform.pathSeparator}tx_${newId()}.$_ext';
        await File(path).writeAsBytes(bytes);
        try {
          text = await LocalTx.transcribe(path, s.txLocalModel, s.txLang);
        } finally {
          try {
            File(path).deleteSync();
          } catch (_) {}
        }
      } else {
        text = await Transcriber.run(s, bytes, 'voice.$_ext');
      }
      b.content = text;
      b.meta['tx'] = mode;
      _tx.text = text;
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  String _fmt(int sec) => '${sec ~/ 60}:${two(sec % 60)}';

  @override
  Widget build(BuildContext context) {
    final has = b.att != null;
    final dur = (b.meta['duration'] ?? 0) as int;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (!has && !_recording)
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.mic),
            label: const Text('Записать'),
          ),
        if (_recording) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Pal.error(context)),
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: Text('Стоп · ${_fmt(_sw.elapsed.inSeconds)}'),
          ),
        ],
        if (has) ...[
          IconButton.filledTonal(
            onPressed: _togglePlay,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
          ),
          const SizedBox(width: 10),
          Text('${_fmt(dur)} · ${humanSize((b.meta['size'] ?? 0) as int)}',
              style: TextStyle(color: Pal.secondary(context))),
          const Spacer(),
          if (_busy)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (widget.store.settings.txMode != 'off')
            TextButton.icon(
              onPressed: _transcribe,
              icon: const Icon(Icons.subtitles_outlined, size: 18),
              label: const Text('Расшифровать'),
            ),
        ],
      ]),
      if (has)
        TextField(
          controller: _tx,
          maxLines: null,
          decoration: const InputDecoration(
              border: InputBorder.none, hintText: 'Транскрипт'),
          onChanged: (v) {
            b.content = v;
            widget.onChanged();
          },
        ),
    ]);
  }
}
