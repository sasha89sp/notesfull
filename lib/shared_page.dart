import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_page.dart';
import 'editor.dart';
import 'groups.dart';
import 'models.dart';
import 'notes_page.dart';
import 'remote.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

part 'shared_page_2.dart';
part 'shared_page_3.dart';


/// Модуль «Общая папка»: список групп (каждая — своя папка на своём WebDAV со своим
/// ключом), создание и вход по приглашению.
class SharedPage extends StatefulWidget {
  final Store store;
  const SharedPage({super.key, required this.store});

  @override
  State<SharedPage> createState() => _SharedPageState();
}

String rightsName(String r) =>
    r == 'view' ? 'только просмотр' : r == 'own' ? 'свои файлы и комментарии' : 'полное редактирование';

class _SharedPageState extends State<SharedPage> {
  Store get s => widget.store;

  Future<void> _create() async {
    final g = await showDialog<Group>(
      context: context,
      builder: (_) => _CreateDialog(store: s),
    );
    if (g == null || !mounted) return;
    setState(() {});
    s.syncAll();
    await showInviteDialog(context, g);
  }

  Future<void> _join() async {
    final c = TextEditingController();
    final nm = TextEditingController(text: s.author);
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if ((d?.text ?? '').trim().startsWith('asrbox-g1')) c.text = d!.text!.trim();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Получить приглашение'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              maxLines: 4,
              minLines: 2,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(labelText: 'Вставьте приглашение'),
            ),
            TextField(
              controller: nm,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(
                  labelText: 'Ваше имя (обязательно)',
                  helperText: 'Без имени доступ не выдаётся'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            TextButton(
                onPressed: c.text.trim().isEmpty || nm.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Войти')),
          ],
        ),
      ),
    );
    final text = c.text;
    final name = nm.text;
    c.dispose();
    nm.dispose();
    if (ok != true || !mounted) return;
    try {
      final g = await GroupsInvite.join(s, text, name);
      if (mounted) {
        setState(() {});
        toast(context, 'Вы в группе «${g.name}»');
      }
      s.syncAll();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final groups = s.settings.groups;
        final sec = Pal.secondary(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                    'Общая папка — место для чата и совместных заметок. Создайте её на своём '
                    'WebDAV или войдите в чужую по приглашению. У каждой группы свой ключ шифрования.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sec)),
              ),
            for (final g in groups)
              AppCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => GroupScreen(store: s, group: g))),
                child: Row(children: [
                  Icon(Icons.folder_shared_outlined,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.name.isEmpty ? 'Общая папка' : g.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                      Text(
                          g.removed
                              ? 'Вас удалили из группы'
                              : '${g.owner == s.settings.profileId ? 'Создатель' : 'Участник'}'
                                  '${g.viewOnly ? ' · только просмотр' : ''} · ${g.folder}',
                          style: TextStyle(color: g.removed ? Pal.error(context) : sec, fontSize: 12)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: sec),
                ]),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(groups.isEmpty ? 'Создать общую папку' : 'Создать ещё одну папку'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _join,
              icon: const Icon(Icons.login),
              label: Text(groups.isEmpty ? 'Войти в общую группу' : 'Войти ещё в одну группу'),
            ),
          ],
        );
      },
    );
  }
}

/// «Копировать приглашение»: права, разовая или многоразовая ссылка, вид (зашифрованно — рекомендуется).
Future<void> showInviteDialog(BuildContext context, Group g) async {
  var rights = 'edit';
  var single = true;
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Future<void> copy(bool enc) async {
          set(() => busy = true);
          try {
            final text = await GroupsInvite.makeInvite(g, encrypted: enc, rights: rights, single: single);
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) {
              Navigator.pop(ctx);
              toast(context, 'Приглашение скопировано');
            }
          } catch (e) {
            if (ctx.mounted) {
              set(() => busy = false);
              toast(ctx, 'Не удалось создать приглашение: $e');
            }
          }
        }

        return AlertDialog(
          title: const Text('Копировать приглашение'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('В приглашении: логин и пароль WebDAV, папка, ключ шифрования и уникальный ID. '
                  'Передавайте только тем, кому доверяете.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              const Text('Права', style: TextStyle(fontWeight: FontWeight.w600)),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Только просмотр'),
                value: 'view',
                groupValue: rights,
                onChanged: (v) => set(() => rights = v!),
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Полное редактирование любого файла'),
                subtitle: const Text('в каждом файле видно, кто его изменил', style: TextStyle(fontSize: 11)),
                value: 'edit',
                groupValue: rights,
                onChanged: (v) => set(() => rights = v!),
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Свои файлы и комментарии'),
                subtitle: const Text('создаёт и правит только свои, комментирует чужие', style: TextStyle(fontSize: 11)),
                value: 'own',
                groupValue: rights,
                onChanged: (v) => set(() => rights = v!),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Разовая')),
                  ButtonSegment(value: false, label: Text('Многоразовая')),
                ],
                selected: {single},
                onSelectionChanged: (v) => set(() => single = v.first),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                    single
                        ? 'По ссылке сможет войти только один человек.'
                        : 'По ссылке смогут войти несколько человек.',
                    style: const TextStyle(fontSize: 12)),
              ),
              FilledButton(
                onPressed: busy ? null : () => copy(true),
                child: const Text('Зашифровано · рекомендуется'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Text('Получатель не увидит логин и пароль от WebDAV: приложение подставит их само.',
                    style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => copy(false),
                child: const Text('В открытом виде'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text('Строка видна полностью, её можно прочитать.', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
        );
      },
    ),
  );
}

/// Файловый менеджер сервера: переходы по папкам, создание папки, выбор.
class _FolderPicker extends StatefulWidget {
  final Remote dav;
  final String start;
  const _FolderPicker({required this.dav, required this.start});

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}