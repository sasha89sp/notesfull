// ▸ Часть media.dart: Блоки изображений, файлов и голоса  [содержит: FileBlockView, VoiceBlockView]
part of 'media.dart';


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