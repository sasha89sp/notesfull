import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ctx_menu.dart';
import 'editor.dart';
import 'event_screen.dart';
import 'models.dart';
import 'note_actions.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// NotePlan-inspired desktop workspace. Reuses the existing note editor,
/// folders, tags, search, event model and event editor; no parallel storage.
class DesktopNotes extends StatefulWidget {
  final Store store;
  final String initial;
  const DesktopNotes({super.key, required this.store, this.initial = 'all'});
  @override
  State<DesktopNotes> createState() => _DesktopNotesState();
}

class _DesktopNotesState extends State<DesktopNotes> {
  late String _sel = widget.initial;
  Note? _note;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _q = '';
  final Set<String> _open = {};
  DateTime _day = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Store get s => widget.store;
  NoteActions get _act => NoteActions(context, s);
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _ink => _dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);
  Color get _muted => _dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
  Color get _line => _dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
  Color get _accent => Theme.of(context).colorScheme.primary;

  @override
  void dispose() { _search.dispose(); _searchFocus.dispose(); super.dispose(); }

  List<Note> _notes() {
    var l = s.notes.where((n) => !n.deleted && !n.isGroup).toList();
    if (_sel == 'fav') l = l.where((n) => n.favorite).toList();
    else if (_sel.startsWith('f:')) l = l.where((n) => n.folder == _sel.substring(2)).toList();
    else if (_sel.startsWith('t:')) l = l.where((n) => n.tags.contains(_sel.substring(2))).toList();
    if (_q.isNotEmpty) l = l.where((n) => s.matches(n, _q)).toList();
    l.sort((a,b) => b.updatedAt.compareTo(a.updatedAt));
    return l;
  }

  void _newNote() {
    final n = Note.create(s.author, s.profileId, 'personal');
    if (_sel.startsWith('f:')) n.folder = _sel.substring(2);
    if (_sel.startsWith('t:')) n.tags.add(_sel.substring(2));
    s.notes.add(n); setState(() => _note = n);
  }
  Future<void> _newFolder([String parent = '']) async {
    final name = await _act.askName('Новая папка');
    if (name == null) return;
    s.addFolder(name, parent); if (parent.isNotEmpty) _open.add(parent); setState(() {});
  }
  void _save() { s.changed(); toast(context, 'Сохранено'); }
  List<CalEvent> get _events => s.events.where((e) => !e.deleted && e.startDt.year == _day.year && e.startDt.month == _day.month && e.startDt.day == _day.day).toList()..sort((a,b)=>a.start.compareTo(b.start));
  Future<void> _openEvent(CalEvent e, {bool isNew = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EventScreen(store: s, event: e, isNew: isNew)));
    if (mounted) setState(() {});
  }
  void _createEvent() {
    final now = DateTime.now();
    final at = DateTime(_day.year, _day.month, _day.day, now.hour + 1);
    _openEvent(CalEvent.create(at), isNew: true);
  }
  String _dayTitle(DateTime d) => '${_weekday[d.weekday-1]}, ${d.day} ${kMonthsNom[d.month-1]}';
  static const _weekday = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье'];

  Widget _miniCalendar() {
    final first = DateTime(_month.year, _month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final today = DateTime.now();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), child: Column(children: [
      Row(children: [Expanded(child: Text('${kMonthsNom[_month.month-1]} ${_month.year}', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontSize: 15))),
        _smallIcon(Icons.chevron_left, () => setState(() => _month = DateTime(_month.year,_month.month-1,1))),
        _smallIcon(Icons.chevron_right, () => setState(() => _month = DateTime(_month.year,_month.month+1,1))),
      ]),
      const SizedBox(height: 10),
      Row(children: [for (final w in ['Пн','Вт','Ср','Чт','Пт','Сб','Вс']) Expanded(child: Center(child: Text(w, style: TextStyle(color:_muted,fontSize:10,fontWeight:FontWeight.w600))))]),
      const SizedBox(height: 5),
      for (var week=0; week<6; week++) Row(children: [for(var col=0;col<7;col++) Builder(builder: (_) {
        final d = start.add(Duration(days: week*7+col));
        final selected = d.year==_day.year && d.month==_day.month && d.day==_day.day;
        final isToday = d.year==today.year && d.month==today.month && d.day==today.day;
        return Expanded(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: ()=>setState(()=>_day=d), child: SizedBox(height:29, child: Center(child: Container(width:27,height:27,decoration:BoxDecoration(color:selected?_accent:null,borderRadius:BorderRadius.circular(20),border:!selected&&isToday?Border.all(color:_accent):null),alignment:Alignment.center,child:Text('${d.day}',style:TextStyle(fontSize:11,color:selected?Colors.white:(d.month==_month.month?_ink:_muted),fontWeight:selected?FontWeight.w700:FontWeight.w400)))))));
      })]),
    ]));
  }
  Widget _smallIcon(IconData icon, VoidCallback tap) => SizedBox(width:26,height:26,child:IconButton(padding:EdgeInsets.zero,visualDensity:VisualDensity.compact,onPressed:tap,icon:Icon(icon,size:17,color:_muted)));

  Widget _navRow(IconData icon, String title, String key, {int? count}) {
    final active = _sel == key;
    return Padding(padding: const EdgeInsets.symmetric(horizontal:10,vertical:1),child:InkWell(borderRadius:BorderRadius.circular(7),onTap:()=>setState(()=>_sel=key),child:Container(height:32,padding:const EdgeInsets.symmetric(horizontal:10),decoration:BoxDecoration(color:active?(_dark?const Color(0xFF27272A):const Color(0xFFE4E4E7)):null,borderRadius:BorderRadius.circular(7)),child:Row(children:[Icon(icon,size:16,color:active?_accent:_muted),const SizedBox(width:9),Expanded(child:Text(title,style:TextStyle(fontSize:13,color:_ink,fontWeight:active?FontWeight.w600:FontWeight.w400))),if(count!=null) _count(count)]))));
  }
  Widget _count(int n) => Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),decoration:BoxDecoration(color:_dark?const Color(0xFF27272A):const Color(0xFFE4E4E7),borderRadius:BorderRadius.circular(10)),child:Text('$n',style:TextStyle(fontSize:10,color:_muted)));
  Widget _folderRow(NoteFolder f, int depth) {
    final key='f:${f.id}'; final active=_sel==key; final kids=s.childFolders(f.id); final expanded=_open.contains(f.id);
    return Column(children:[InkWell(onTap:()=>setState(()=>_sel=key),onSecondaryTapDown:(d) async {final a=await showCtx(context,d.globalPosition,_act.folderItems(f));if(a!=null){if(a=='sub')_open.add(f.id);await _act.runFolder(f,a);if(mounted)setState((){});}},child:Container(height:30,padding:EdgeInsets.only(left:12+depth*12,right:10),color:active?(_dark?const Color(0xFF27272A):const Color(0xFFE4E4E7)):null,child:Row(children:[Icon(expanded?Icons.folder_open_outlined:Icons.folder_outlined,size:15,color:active?_accent:_muted),const SizedBox(width:8),Expanded(child:Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12.5,color:_ink))),_count(s.notesIn(f.id)),if(kids.isNotEmpty)_smallIcon(expanded?Icons.expand_less:Icons.expand_more,()=>setState(()=>expanded?_open.remove(f.id):_open.add(f.id)))]))),if(expanded) ...kids.map((x)=>_folderRow(x,depth+1))]);
  }
  Widget _noteTile(Note n) {
    final active=_note?.id==n.id;
    return InkWell(onTap:()=>setState(()=>_note=n),onSecondaryTapDown:(d) async {final a=await showCtx(context,d.globalPosition,_act.noteItems(n));if(a==null)return;final r=await _act.runNote(n,a);if(!mounted)return;setState((){if(r=='open')_note=n;if(r=='deleted'&&_note?.id==n.id)_note=null;});},child:Container(padding:const EdgeInsets.fromLTRB(12,8,10,8),decoration:BoxDecoration(color:active?(_dark?const Color(0xFF27272A):const Color(0xFFE0E7FF)):null,border:Border(bottom:BorderSide(color:_line.withOpacity(.65)))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(n.title.isEmpty?'Без названия':n.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12.5,fontWeight:FontWeight.w600,color:_ink))),if(n.favorite)const Icon(Icons.star,size:12,color:Color(0xFFD97706))]),const SizedBox(height:3),Text(n.preview(58),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,color:_muted)),Text(fmtDate(n.updatedAt),style:TextStyle(fontSize:10,color:_muted))])));
  }

  Widget _sidebar() {
    final tags=<String>{}; for(final n in s.notes.where((n)=>!n.deleted&&!n.isGroup)){tags.addAll(n.tags);} final tl=tags.toList()..sort();
    final notes=_notes();
    return Container(color:_dark?const Color(0xFF18181B):const Color(0xFFF4F4F5),child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,18,14,10),child:Row(children:[const Icon(Icons.circle,size:10,color:Color(0xFFEF4444)),const SizedBox(width:6),const Icon(Icons.circle,size:10,color:Color(0xFFF59E0B)),const SizedBox(width:6),const Icon(Icons.circle,size:10,color:Color(0xFF22C55E)),const Spacer(),Icon(Icons.notes_rounded,size:18,color:_muted)])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:SizedBox(width:double.infinity,height:38,child:OutlinedButton.icon(style:OutlinedButton.styleFrom(backgroundColor:_dark?const Color(0xFF27272A):Colors.white,foregroundColor:_ink,side:BorderSide(color:_line.withOpacity(.8)),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8))),onPressed:_newNote,icon:Icon(Icons.add,color:_accent,size:18),label:const Text('Новая заметка',style:TextStyle(fontSize:13,fontWeight:FontWeight.w600))))),
      _miniCalendar(),
      _navRow(Icons.sunny,'Сегодня','all',count:s.notes.where((n)=>!n.deleted&&!n.isGroup).length),
      _navRow(Icons.calendar_view_week,'Неделя','all'),
      _navRow(Icons.calendar_month_outlined,'Месяц','all'),
      _navRow(Icons.bar_chart,'Год','all'),
      Padding(padding:const EdgeInsets.fromLTRB(16,12,16,6),child:Row(children:[Expanded(child:Text('ПРОЕКТЫ',style:TextStyle(fontSize:10,fontWeight:FontWeight.w700,letterSpacing:.7,color:_muted))),_smallIcon(Icons.create_new_folder_outlined,_newFolder)])),
      Expanded(child:ListView(padding:EdgeInsets.zero,children:[_navRow(Icons.notes,'Все заметки','all'),_navRow(Icons.star_outline,'Избранное','fav'),...s.childFolders('').map((f)=>_folderRow(f,0)),if(tl.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(16,12,16,5),child:Text('ТЕГИ',style:TextStyle(fontSize:10,fontWeight:FontWeight.w700,letterSpacing:.7,color:_muted))),...tl.map((t)=>_navRow(Icons.tag,t,'t:$t')),
        Padding(padding:const EdgeInsets.fromLTRB(12,12,12,4),child:TextField(controller:_search,focusNode:_searchFocus,onChanged:(v)=>setState(()=>_q=v.trim()),style:TextStyle(fontSize:12,color:_ink),decoration:InputDecoration(isDense:true,hintText:'Поиск заметок',hintStyle:TextStyle(color:_muted,fontSize:12),prefixIcon:Icon(Icons.search,size:16,color:_muted),contentPadding:const EdgeInsets.symmetric(vertical:8),filled:true,fillColor:_dark?const Color(0xFF27272A):Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:_line)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:_line))))),
        Padding(padding:const EdgeInsets.fromLTRB(14,9,12,4),child:Text('ЗАМЕТКИ  ·  ${notes.length}',style:TextStyle(fontSize:10,fontWeight:FontWeight.w700,letterSpacing:.6,color:_muted))),...notes.take(80).map(_noteTile),
      ])),
    ]));
  }

  Widget _editor() {
    final n=_note;
    return Container(color:_dark?const Color(0xFF09090B):const Color(0xFFFAFAF9),child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(34,20,24,10),child:Row(children:[Expanded(child:Text(_dayTitle(_day),style:TextStyle(fontSize:25,fontWeight:FontWeight.w700,letterSpacing:-.5,color:_ink))),Text('${_day.year}  ·  Неделя ${_weekNumber(_day)}',style:TextStyle(fontSize:12,color:_muted)),const SizedBox(width:12),_smallIcon(Icons.search,()=>_searchFocus.requestFocus()),_smallIcon(Icons.note_add_outlined,_newNote),_smallIcon(Icons.more_horiz,()=>_save())])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:34),child:Divider(height:1,color:_line)),
      Expanded(child:n==null||n.deleted?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.edit_note,size:42,color:_muted),const SizedBox(height:10),Text('Выберите заметку или создайте новую',style:TextStyle(color:_muted,fontSize:13)),const SizedBox(height:12),FilledButton.icon(onPressed:_newNote,icon:const Icon(Icons.add),label:const Text('Новая заметка'))])):Padding(padding:const EdgeInsets.fromLTRB(26,12,26,12),child:EditorScreen(key:ValueKey(n.id),store:s,note:n,embedded:true,onClosed:()=>setState(()=>_note=null)))),
    ]));
  }
  int _weekNumber(DateTime date) { final d=DateTime(date.year,date.month,date.day); final thursday=d.add(Duration(days:4-d.weekday)); final first=DateTime(thursday.year,1,4); return 1+((thursday.difference(first).inDays-(first.weekday-1))/7).floor(); }

  Widget _schedule() {
    final ev=_events; final all=ev.where((e)=>e.allDay).toList(); final timed=ev.where((e)=>!e.allDay).toList();
    return Container(color:_dark?const Color(0xFF111113):Colors.white,child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(18,22,14,14),child:Row(children:[Expanded(child:Text('РАСПИСАНИЕ',style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,letterSpacing:.8,color:_muted))),_smallIcon(Icons.add,_createEvent)])),
      if(all.isNotEmpty) ...all.map((e)=>_eventCard(e)),
      Expanded(child:ListView.builder(padding:const EdgeInsets.only(bottom:20),itemCount:13,itemBuilder:(context,index){final hour=7+index;final items=timed.where((e)=>e.startDt.hour==hour).toList();return SizedBox(height:68,child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[SizedBox(width:58,child:Padding(padding:const EdgeInsets.only(top:0,left:14),child:Text('${hour.toString().padLeft(2,'0')}:00',style:TextStyle(fontSize:10,color:_muted,fontFeatures:const [])))),Expanded(child:Container(decoration:BoxDecoration(border:Border(top:BorderSide(color:_line.withOpacity(.8)))),padding:const EdgeInsets.fromLTRB(0,4,12,4),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[for(final e in items)_eventCard(e)])))]));})),
    ]));
  }
  Widget _eventCard(CalEvent e) {
    final colors=e.isTask?(const Color(0xFFFFF1DB),const Color(0xFFD97706)):(const Color(0xFFE0EAFF),const Color(0xFF4F46E5));
    final bg=_dark?colors.$2.withOpacity(.17):colors.$1;
    final time=e.allDay?'Весь день': '${fmtTime(e.startDt)} – ${fmtTime(e.endDt)}';
    return Padding(padding:const EdgeInsets.only(bottom:5),child:Material(color:bg,borderRadius:BorderRadius.circular(7),child:InkWell(borderRadius:BorderRadius.circular(7),onTap:()=>_openEvent(e),child:Container(padding:const EdgeInsets.fromLTRB(9,7,8,7),decoration:BoxDecoration(border:Border(left:BorderSide(color:colors.$2,width:3)),borderRadius:BorderRadius.circular(7)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(e.title.isEmpty?'Без названия':e.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11.5,fontWeight:FontWeight.w600,color:_dark?const Color(0xFFFAFAFA):const Color(0xFF1E293B))),const SizedBox(height:3),Text(time,style:TextStyle(fontSize:10,color:_dark?const Color(0xFFA1A1AA):const Color(0xFF64748B)))])))));
  }

  Map<ShortcutActivator,VoidCallback> get _keys { final m=<ShortcutActivator,VoidCallback>{}; for(final (ctrl,meta) in [(true,false),(false,true)]) {m[SingleActivator(LogicalKeyboardKey.keyN,control:ctrl,meta:meta)]=_newNote;m[SingleActivator(LogicalKeyboardKey.keyF,control:ctrl,meta:meta)]=()=>_searchFocus.requestFocus();m[SingleActivator(LogicalKeyboardKey.keyS,control:ctrl,meta:meta)]=_save;} return m; }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(bindings:_keys,child:Focus(autofocus:true,child:AnimatedBuilder(animation:s,builder:(context,_)=>LayoutBuilder(builder:(context,c){
    final compact=c.maxWidth<1050; final narrow=c.maxWidth<760;
    return Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(!narrow)SizedBox(width:compact?220:260,child:_sidebar()) else Expanded(flex:4,child:_sidebar()),
      VerticalDivider(width:1,thickness:1,color:_line),
      Expanded(flex:compact?5:7,child:_editor()),
      if(!compact)VerticalDivider(width:1,thickness:1,color:_line),
      if(!compact)SizedBox(width:300,child:_schedule()),
    ]);
  }))));
}
