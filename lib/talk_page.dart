import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:table_calendar/table_calendar.dart';

import 'utils/database_helper.dart';
import 'widgets/message.dart';
import 'menu/icon_change_page.dart';
import 'menu/call_me_page.dart';
import 'menu/favorites_page.dart';
import 'menu/media_page.dart';
import 'utils/helper.dart';
import 'menu/text_search_page.dart';

class TalkPage extends StatefulWidget {
  final Map<String, dynamic>? savedState;
  final String? name;

  const TalkPage({Key? key, required this.name, this.savedState}) : super(key: key);

  @override
  _TalkPageState createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  final dbHelper = DatabaseHelper();

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  /// 「List<Map<String, dynamic>> messages」が可変なリストになるように扱う
  List<Map<String, dynamic>> messages = [];
  bool isLoading = false;
  String? iconPath;
  String? callMeName;

  /// 現在保持している中で最も古いメッセージID (IDが最小)
  /// reverse:true で id DESC 順に格納しているので、末尾が最古
  int? oldestIdSoFar;

  @override
  void initState() {
    super.initState();
    _loadIcon();
    _loadCallMeName();

    // 前の画面から状態を復元
    if (widget.savedState?["messages"]?.isNotEmpty ?? false) {
      // 1) savedState["messages"] はイミュータブルかもしれないので map(...).toList() でコピー
      final savedList = widget.savedState!["messages"] as List;
      messages = savedList.map((row) => Map<String, dynamic>.from(row)).toList();
      oldestIdSoFar = messages.isNotEmpty ? messages.last['id'] as int : null;

      iconPath = widget.savedState?["iconPath"] ?? "assets/images/icon.png";
    } else {
      // 初回ロード: 最新n件のみ取得
      _loadInitialMessages();
    }

    // 上にスクロールして古いメッセージを読み込むリスナー
    _itemPositionsListener.itemPositions.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_scrollListener);
    super.dispose();
  }

  Future<void> _loadCallMeName() async {
    final name = await dbHelper.getCallMeName(widget.name ?? '');
    setState(() {
      callMeName = name ?? "あなた";
    });
  }

  Future<void> _loadIcon() async {
    final path = await dbHelper.getIconPath(widget.name ?? '');
    setState(() {
      iconPath = path ?? "assets/images/icon.png";
    });
  }

  /// 最新20件をロード
  Future<void> _loadInitialMessages() async {
    setState(() => isLoading = true);

    // 1) DBクエリ結果を取得
    final newestRaw = await dbHelper.getNewestMessages(widget.name, 20);
    // 2) map(...).toList() で可変リストに変換
    final newest = newestRaw.map((row) => Map<String, dynamic>.from(row)).toList();

    setState(() {
      messages = newest; // id DESC (新しい順)
      if (messages.isNotEmpty) {
        oldestIdSoFar = messages.last['id'] as int; // 末尾が最古ID
      }
      isLoading = false;
    });
  }

  /// さらに古いメッセージを読み込む (IDベース)
  Future<void> _loadOlderMessages() async {
    if (isLoading) return;
    if (oldestIdSoFar == null) return; // まだ何もない

    setState(() => isLoading = true);

    // DBから "oldestIdSoFar より古い" 投稿を10件 (id DESC)
    final olderRaw = await dbHelper.getOlderMessagesById(widget.name, oldestIdSoFar!, 10);
    final older = olderRaw.map((row) => Map<String, dynamic>.from(row)).toList();

    if (older.isNotEmpty) {
      setState(() {
        // messages は既に可変リストなので、.addAll() でOK
        messages.addAll(older);
        oldestIdSoFar = messages.last['id'] as int;
      });
    }

    setState(() => isLoading = false);
  }

  /// 日付検索: 指定日付より古い投稿をすべてロード → そこへスクロール
  Future<void> _jumpToDate(DateTime date) async {
    setState(() => isLoading = true);

    // 1週間マイナス
    final extendedDate = date.subtract(const Duration(days: 7));
    // DBから "date より新しい(または同日)" 投稿を全件 (id DESC)
    final resultRaw = await dbHelper.getMessagesSinceDate(widget.name, extendedDate);
    
    final result = resultRaw.map((row) => Map<String, dynamic>.from(row)).toList();

    setState(() {
      messages = result; // 表示を置き換え
      oldestIdSoFar = messages.isNotEmpty ? messages.last['id'] as int : null;
      isLoading = false;
    });

    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("該当するメッセージがありません")),
      );
      return;
    }

    // 指定日付に最も近い投稿へスクロール
    final targetIndex = _findClosestIndex(date);
    
    if (targetIndex == -1) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    });
  }

  /// messagesから「dateに最も近い投稿」のindexを返す
  int _findClosestIndex(DateTime date) {
    int closestIndex = -1;
    int minDiff = 99999999999;
    for (int i = 0; i < messages.length; i++) {
      final msgDate = DateTime.parse(messages[i]['date']);
      final diff = (msgDate.millisecondsSinceEpoch - date.millisecondsSinceEpoch).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  /// 上にスクロールしたら古いメッセージを追加読み込み
  void _scrollListener() {
    if (isLoading) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // もっとも大きいindex (末尾)を取得
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

    // reverse:true なので index=0 が画面の最"上"(最新)、
    // index=(messages.length-1) が画面の最"下"(最古)
    // → 末尾(最古)付近に来たら古いメッセージをロード
    if (maxIndex >= messages.length - 2) {
      _loadOlderMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name ?? ''),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handlePop,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: _openSettingsMenu,
          ),
        ],
      ),
      body: Stack(
        children: [
          ScrollablePositionedList.separated(
            reverse: true,
            initialScrollIndex: widget.savedState?["scrollIndex"] ?? 0,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final row = messages[index];
              final isFavorite = (row['is_favorite'] == 1);

              return GestureDetector(
                onLongPress: () async {
                  final newStatus = !isFavorite;
                  await dbHelper.updateFavoriteStatus(row['id'] as int, newStatus);
                  setState(() {
                    messages[index]['is_favorite'] = newStatus ? 1 : 0;
                  });
                },
                child: Message(
                  message: replacePlaceHolders(row['text'], callMeName ?? "あなた").trim(),
                  senderName: row['name'],
                  time: DateTime.parse(row['date']),
                  avatarAssetPath: iconPath ?? "assets/images/icon.png",
                  mediaPath: row['filepath'],
                  thumbPath: row['thumb_filepath'],
                  isFavorite: isFavorite,
                ),
              );
            },
          ),
          if (isLoading)
            const Positioned(
              top: 0,
              right: 0,
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (messages.isNotEmpty) {
            _itemScrollController.scrollTo(
              index: 0, // 一番下（最古のメッセージ）にスクロール
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          }
        },
        child: const Icon(Icons.arrow_downward),
      ),
    );
  }

  void _handlePop() {
    // 表示中の先頭に近いアイテムの index を取得
    final positions = _itemPositionsListener.itemPositions.value;
    int? scrollIndex;
    if (positions.isNotEmpty) {
      // 画面上に表示されているアイテムのうち、もっとも先頭にある index を選ぶ
      scrollIndex = positions
          .where((position) => position.itemLeadingEdge >= 0)
          .map((position) => position.index)
          .reduce((a, b) => a < b ? a : b);
    }

    final stateToSave = {
      'messages': messages,
      'iconPath': iconPath,
      'scrollIndex': scrollIndex ?? 0,
    };
    Navigator.pop(context, stateToSave);
  }


  void _openSettingsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 30.0),
          child: Wrap(
            children: [
              _buildMenuItem(Icons.calendar_today, "日付検索", () => _onMenuTap("Date Search")),
              _buildMenuItem(Icons.text_fields, "テキスト検索", () => _onMenuTap("Text Search")),
              _buildMenuItem(Icons.star_border, "お気に入り", () => _onMenuTap("Favorites")),
              _buildMenuItem(Icons.image, "メディア一覧", () => _onMenuTap("Media")),
              _buildMenuItem(Icons.account_circle, "アイコン", () => _onMenuTap("Icon")),
              _buildMenuItem(Icons.edit, "呼ばれたい名前", () => _onMenuTap("Call me")),
            ],
          ),
        );
      },
    );
  }

  void _onMenuTap(String action) {
    Navigator.pop(context); // メニューを閉じる

    switch (action) {
      case "Icon":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IconChangePage(
              talkName: widget.name ?? '',
              currentIconPath: iconPath ?? "assets/images/icon.png",
              onIconChanged: (newPath) {
                setState(() {
                  iconPath = newPath;
                });
              },
            ),
          ),
        );
        break;
      case "Call me":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallMePage(
              name: widget.name ?? '',
              currentCallMe: callMeName,
              onCallMeChanged: (newName) {
                setState(() {
                  callMeName = newName;
                });
              },
            ),
          ),
        );
        break;
      case "Favorites":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FavoritesPage(
              name: widget.name ?? '',
              iconPath: iconPath ?? "assets/images/icon.png",
              callMeName: callMeName ?? "あなた",
            ),
          ),
        );
        break;
      case "Media":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaPage(
              name: widget.name ?? '',
              iconPath: iconPath ?? "assets/images/icon.png",
              callMeName: callMeName ?? "あなた",
            ),
          ),
        );
        break;
      case "Date Search":
        _showDateSearchCalendar();
        break;

      case "Text Search":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextSearchPage(
              name: widget.name,
              iconPath: iconPath ?? "assets/images/icon.png",
              callMeName: callMeName ?? "あなた",
            )
          )
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$action tapped")));
    }
  }

  void _showDateSearchCalendar() {
    final screenHeight = MediaQuery.of(context).size.height;
    // 現在画面に見えている投稿の中央値の日付を取得
    DateTime initialCalendarDate = DateTime.now();
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final visiblePositions = positions.toList();
      visiblePositions.sort((a, b) => a.index.compareTo(b.index));
      final medianIndex = visiblePositions[visiblePositions.length ~/ 2].index;
      initialCalendarDate = DateTime.parse(messages[medianIndex]['date']);
    }
    
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        final screenHeight = MediaQuery.of(context).size.height;
        return SafeArea(
          child: SizedBox(
            height: screenHeight * 0.55, // 高さを50%にして下部の余白を減少
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: _CalendarBottomSheet(
                    initialDate: initialCalendarDate,
                    onDateSelected: (selectedDate) {
                      // 日付選択時の処理（既存の処理）
                      _jumpToDate(selectedDate);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(IconData icon, String text, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(text),
      onTap: onTap,
    );
  }
}

class _CalendarBottomSheet extends StatefulWidget {
  final Function(DateTime) onDateSelected;
  final DateTime? initialDate; // 初期表示する日付を受け取る

  const _CalendarBottomSheet({
    Key? key,
    required this.onDateSelected,
    this.initialDate,
  }) : super(key: key);

  @override
  State<_CalendarBottomSheet> createState() => _CalendarBottomSheetState();
}

class _CalendarBottomSheetState extends State<_CalendarBottomSheet> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    // 初期表示は渡された日付、なければ現在日付
    _focusedDay = widget.initialDate ?? DateTime.now();
    _selectedDay = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      focusedDay: _focusedDay,
      firstDay: DateTime(2017),
      lastDay: DateTime(2050),
      locale: 'ja_JP',
      calendarFormat: CalendarFormat.month,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        widget.onDateSelected(selectedDay);
      },
    );
  }
}