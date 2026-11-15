part of 'md.dart';


class _MdDocState extends State<MdDoc> {
  final List<TapGestureRecognizer> _recs = [];

  @override
  void dispose() {
    _disposeRecs();
    super.dispose();
  }

  static final RegExp _inl = RegExp(
    r'\\([\\`*_{}\[\]()#+\-.!~=^|<>])' // 1 экранирование
    r'|!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)' // 2 alt, 3 src
    r'|\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)' // 4 текст, 5 адрес
    r'|`([^`]+)`' // 6 код
    r'|\*\*(.+?)\*\*' // 7 жирный
    r'|__(.+?)__' // 8 жирный
    r'|~~(.+?)~~' // 9 зачёркнутый
    r'|==(.+?)==' // 10 выделение
    r'|\+\+(.+?)\+\+' // 11 подчёркнутый
    r'|\*([^*\s][^*]*?)\*' // 12 курсив
    r'|(?<![A-Za-z0-9_])_([^_\s][^_]*?)_(?![A-Za-z0-9_])' // 13 курсив
    r'|~([^~\s]+)~' // 14 нижний индекс
    r'|\^([^\^\s]+)\^' // 15 верхний индекс
    r'|<(https?://[^>\s]+)>' // 16 ссылка в <>
    r'|(https?://[^\s<>()]+)' // 17 голая ссылка
    r'|(<br\s*/?>)', // 18 перенос
  );

  static final RegExp _tagRe =
      RegExp(r'(^|\s)(#[\p{L}][\p{L}\p{N}_/\-]*)|(\[\[[^\]\n]+\]\])', unicode: true);

  @override
  Widget build(BuildContext context) {
    _disposeRecs();
    final base = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 17))
        .copyWith(fontSize: 17, height: 1.4);
    final blocks = mdParse(widget.text.replaceAll('\r\n', '\n').split('\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) _block(blocks[i], base, top: i == 0),
      ],
    );
  }}