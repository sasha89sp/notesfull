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
import 'model_dl.dart';
import 'models.dart';
import 'store.dart';
import 'transcribe.dart';
import 'util.dart';
import 'widgets.dart';

part 'media_2.dart';
part 'media_3.dart';


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