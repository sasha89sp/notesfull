// ▸ Часть media.dart: Блоки изображений, файлов и голоса  [содержит: _VoiceBlockViewState]
part of 'media.dart';


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
          if (await ModelDl.have(s.txLocalModel) == 0 && mounted) {
            toast(context, 'Модель не скачана: сначала Настройки → Голос → Скачать');
          }
          text = await LocalTx.transcribe(path, s.txLocalModel, s.txLang)
              .timeout(const Duration(minutes: 15), onTimeout: () => throw 'Расшифровка не завершилась за 15 минут');
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