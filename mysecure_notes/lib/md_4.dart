part of 'md.dart';


class _MdImageState extends State<_MdImage> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = widget.src;
    if (s.startsWith(':/') && widget.store != null) {
      final id = s.substring(2).split(RegExp(r'[#\s]')).first;
      _bytes = await widget.store!.readAttachment(id);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.src;
    final w = MediaQuery.of(context).size.width - 56;
    if (s.startsWith('http')) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: 420),
        child: Image.network(s,
            errorBuilder: (_, __, ___) => Text('[изображение: ${widget.alt}]')),
      );
    }
    if (!_loaded) return const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2));
    if (_bytes == null) {
      return Text('[нет вложения: ${widget.alt.isEmpty ? s : widget.alt}]',
          style: TextStyle(color: Pal.secondary(context)));
    }
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(child: Image.memory(_bytes!)),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: 420),
        child: Image.memory(_bytes!,
            errorBuilder: (_, __, ___) => Text('[не изображение: ${widget.alt}]')),
      ),
    );
  }
}