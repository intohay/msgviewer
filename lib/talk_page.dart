import 'dart:async';
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

class _TalkPageState extends State<TalkPage> with WidgetsBindingObserver {
  final dbHelper = DatabaseHelper();

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  
  Timer? _saveTimer;

  /// 「List<Map<String, dynamic>> messages」が可変なリストになるように扱う
  List<Map<String, dynamic>> messages = [];
  bool isLoading = false;
  String? iconPath;
  String? callMeName;

  /// 現在保持している中で最も古いメッセージID (IDが最小)
  /// reverse:true で id DESC 順に格納しているので、末尾が最古
  int? oldestIdSoFar;
  
  /// 現在保持している中で最も新しいメッセージID (IDが最大)
  int? newestIdSoFar;
  
  /// 最下部にいるかどうかを管理する状態変数
  bool isAtBottom = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);  // ライフサイクル監視を追加
    _loadIcon();
    _loadCallMeName();

    // 前の画面から状態を復元
    if (widget.savedState?["messages"]?.isNotEmpty ?? false) {
      // 1) savedState["messages"] はイミュータブルかもしれないので map(...).toList() でコピー
      final savedList = widget.savedState!["messages"] as List;
      final tempMessages = savedList.map((row) => Map<String, dynamic>.from(row)).toList();
      
      // パス変換を適用
      _convertMessagesPathsAsync(tempMessages);
      
      oldestIdSoFar = messages.isNotEmpty ? messages.last['id'] as int : null;

      iconPath = widget.savedState?["iconPath"] ?? "assets/images/icon.png";
      print('TalkPage: Loaded with messages and scroll index ${widget.savedState?["scrollIndex"] ?? 0}');
    } else {
      // スクロール位置のみ保存されている場合も考慮
      final savedScrollIndex = widget.savedState?["scrollIndex"];
      if (savedScrollIndex != null && savedScrollIndex > 0) {
        print('TalkPage: Loading all messages and jumping to saved index $savedScrollIndex');
        _loadAllMessagesAndJump(savedScrollIndex);
      } else {
        print('TalkPage: No saved state, loading initial messages');
        _loadInitialMessages();
      }
    }

    // 上にスクロールして古いメッセージを読み込むリスナー
    _itemPositionsListener.itemPositions.addListener(_scrollListener);
    // スクロール位置の変更を監視
    _itemPositionsListener.itemPositions.addListener(_onScrollPositionChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(_scrollListener);
    _itemPositionsListener.itemPositions.removeListener(_onScrollPositionChanged);
    _saveTimer?.cancel();
    // 破棄される前に最後の保存
    _saveScrollPosition();
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
        newestIdSoFar = messages.first['id'] as int; // 先頭が最新ID
      }
      isLoading = false;
    });
    
    // 保存されたスクロール位置があれば、初期ロード後にスクロール
    final savedScrollIndex = widget.savedState?["scrollIndex"];
    if (savedScrollIndex != null && savedScrollIndex > 0 && messages.isNotEmpty) {
      final targetIndex = savedScrollIndex.clamp(0, messages.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: targetIndex);
          print('TalkPage: Jumped to saved scroll index $targetIndex');
        }
      });
    }
  }

  // savedStateのメッセージのパスを変換
  Future<void> _convertMessagesPathsAsync(List<Map<String, dynamic>> tempMessages) async {
    // パス変換を適用
    final convertedMessages = await dbHelper.convertPathsToAbsolute(tempMessages);
    setState(() {
      messages = convertedMessages;
    });
  }

  /// 全メッセージをロードして指定インデックスにジャンプ
  Future<void> _loadAllMessagesAndJump(int savedIndex) async {
    setState(() => isLoading = true);

    // 全メッセージを取得（パス変換も含む）
    final messagesRaw = await dbHelper.getAllMessagesForTalk(widget.name);
    final loadedMessages = messagesRaw.map((row) => Map<String, dynamic>.from(row)).toList();

    setState(() {
      messages = loadedMessages;
      if (messages.isNotEmpty) {
        oldestIdSoFar = messages.last['id'] as int;
        newestIdSoFar = messages.first['id'] as int;
      }
      isLoading = false;
    });
    
    // 保存されたインデックスが有効な範囲内にあることを確認してジャンプ
    final targetIndex = savedIndex.clamp(0, messages.isEmpty ? 0 : messages.length - 1);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollController.isAttached && messages.isNotEmpty) {
        _itemScrollController.jumpTo(index: targetIndex);
        print('TalkPage: Jumped to saved index $targetIndex (out of ${messages.length} messages)');
      }
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

  /// さらに新しいメッセージを読み込む (IDベース) 
  Future<void> _loadNewerMessages() async {
    if (isLoading) return;
    if (newestIdSoFar == null) return;

    setState(() => isLoading = true);

    // 現在の最新IDより新しいメッセージを取得
    final newerRaw = await dbHelper.getNewerMessages(widget.name, newestIdSoFar!, 20);
    final newer = newerRaw.map((row) => Map<String, dynamic>.from(row)).toList();

    setState(() {
      if (newer.isNotEmpty) {
        // 新しいメッセージを先頭に追加
        messages.insertAll(0, newer);
        newestIdSoFar = newer.first['id'] as int;
      }
      isLoading = false;
    });
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

  /// スクロールしたらメッセージを追加読み込み
  void _scrollListener() {
    if (isLoading) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // もっとも小さいindex (先頭)と大きいindex (末尾)を取得
    final minIndex = positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

    // reverse:true なので index=0 が画面の最"上"(最新)、
    // index=(messages.length-1) が画面の最"下"(最古)
    
    // 最下部にいるかどうかを判定（index=0が表示されているかどうか）
    final atBottom = minIndex == 0;
    if (isAtBottom != atBottom) {
      setState(() {
        isAtBottom = atBottom;
      });
    }
    
    // 先頭(最新)付近に来たら新しいメッセージをロード
    if (minIndex <= 1 && newestIdSoFar != null) {
      _loadNewerMessages();
    }
    
    // 末尾(最古)付近に来たら古いメッセージをロード
    if (maxIndex >= messages.length - 2) {
      _loadOlderMessages();
    }
  }

  // スクロール位置が変更された時の処理
  void _onScrollPositionChanged() {
    // 既存のタイマーをキャンセル
    _saveTimer?.cancel();
    
    // 1秒後にスクロール位置を保存（デバウンス処理）
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveScrollPosition();
    });
  }

  // スクロール位置を保存
  Future<void> _saveScrollPosition() async {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty && messages.isNotEmpty) {
      // 画面上に表示されているアイテムのうち、もっとも先頭にある index を選ぶ
      final scrollIndex = positions
          .where((position) => position.itemLeadingEdge >= 0)
          .map((position) => position.index)
          .reduce((a, b) => a < b ? a : b);
      
      print('Auto-saving scroll position: index=$scrollIndex for ${widget.name}');
      await dbHelper.setScrollIndex(widget.name ?? '', scrollIndex);
    }
  }

  // アプリのライフサイクル変更時の処理
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // アプリがバックグラウンドに移行する時に保存
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached) {
      print('App going to background/detached - saving scroll position');
      _saveScrollPosition();
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
            initialScrollIndex: messages.isNotEmpty 
                ? (widget.savedState?["scrollIndex"] ?? 0).clamp(0, messages.length - 1)
                : 0,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            padding: const EdgeInsets.only(bottom: 80), // 最下部にマージンを追加
            itemBuilder: (context, index) {
              final row = messages[index];
              final isFavorite = (row['is_favorite'] == 1);
              
              // メディアファイルを持つメッセージのみを抽出し、逆順にする
              // （PageViewは左スワイプでindex増加、右スワイプでindex減少なので）
              final allMediaMessages = messages.where((msg) {
                final path = msg['filepath'] as String?;
                return path != null && 
                       path.isNotEmpty && 
                       (path.endsWith('.jpg') || 
                        path.endsWith('.png') || 
                        path.endsWith('.mp4'));
              }).toList().reversed.toList();
              
              // 現在のメッセージがメディアを持つ場合、そのインデックスを取得
              int? currentMediaIndex;
              if (row['filepath'] != null && row['filepath'].isNotEmpty) {
                final path = row['filepath'] as String;
                if (path.endsWith('.jpg') || path.endsWith('.png') || path.endsWith('.mp4')) {
                  currentMediaIndex = allMediaMessages.indexWhere((msg) => msg['id'] == row['id']);
                }
              }

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
                  allMedia: currentMediaIndex != null ? allMediaMessages : null,
                  currentMediaIndex: currentMediaIndex,
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
      floatingActionButton: !isAtBottom ? FloatingActionButton(
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
      ) : null,
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
    print('TalkPage: Returning with scroll index ${scrollIndex ?? 0}');
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
              _buildMenuItem(Icons.drive_file_rename_outline, "トーク名を編集", () => _onMenuTap("Edit Name")),
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
        ).then((result) {
          // メディア一覧から戻ってきた時にジャンプ指定があれば実行
          if (result != null && result['jumpToDate'] != null) {
            _jumpToDate(result['jumpToDate']);
          }
        });
        break;
      case "Date Search":
        _showDateSearchCalendar();
        break;
      
      case "Edit Name":
        _showEditNameDialog();
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
        ).then((result) {
          // テキスト検索から戻ってきた時にジャンプ指定があれば実行
          if (result != null && result['jumpToDate'] != null) {
            _jumpToDate(result['jumpToDate']);
          }
        });
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$action tapped")));
    }
  }

  int _getCurrentScrollIndex() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // 表示中のアイテムの中で最も上にあるものを取得
      return positions
          .map((position) => position.index)
          .reduce((value, element) => value < element ? value : element);
    }
    return 0;
  }

  void _showEditNameDialog() async {
    final TextEditingController nameController = TextEditingController(text: widget.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('トーク名を編集'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新しい名前',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    
    if (newName != null && newName.isNotEmpty && newName != widget.name) {
      try {
        // データベースでトーク名を更新
        await dbHelper.updateTalkName(widget.name ?? '', newName);
        
        // 画面を更新して新しい名前を反映
        if (mounted) {
          // ホーム画面に戻る（新しい名前で再度開く必要がある）
          Navigator.pop(context, {
            'nameChanged': true,
            'oldName': widget.name,
            'newName': newName,
            'scrollIndex': _getCurrentScrollIndex(),
            'iconPath': iconPath ?? "assets/images/icon.png",
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('トーク名を「$newName」に変更しました')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('名前の変更中にエラーが発生しました: $e')),
          );
        }
      }
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
    
    // トーク履歴の最小・最大日付を取得
    DateTime? minDate;
    DateTime? maxDate;
    if (messages.isNotEmpty) {
      // messagesは新しい順なので、最初が最新、最後が最古
      maxDate = DateTime.parse(messages.first['date']);
      minDate = DateTime.parse(messages.last['date']);
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
                    minDate: minDate,
                    maxDate: maxDate,
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
  final DateTime? minDate; // 最小日付
  final DateTime? maxDate; // 最大日付

  const _CalendarBottomSheet({
    Key? key,
    required this.onDateSelected,
    this.initialDate,
    this.minDate,
    this.maxDate,
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
    
    // focusedDayが範囲内にあることを確認
    if (widget.minDate != null && _focusedDay.isBefore(widget.minDate!)) {
      _focusedDay = widget.minDate!;
    }
    if (widget.maxDate != null && _focusedDay.isAfter(widget.maxDate!)) {
      _focusedDay = widget.maxDate!;
    }
    
    _selectedDay = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // カスタムヘッダー
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左矢印 - 最小月に達したら非表示
              SizedBox(
                width: 48,
                child: (widget.minDate != null &&
                        _focusedDay.year == widget.minDate!.year &&
                        _focusedDay.month == widget.minDate!.month)
                    ? null // 非表示
                    : IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setState(() {
                            final newDate = DateTime(
                              _focusedDay.year,
                              _focusedDay.month - 1,
                            );
                            _focusedDay = newDate;
                          });
                        },
                      ),
              ),
              GestureDetector(
                onTap: () => _showYearMonthPicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_focusedDay.year}年${_focusedDay.month}月',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
              ),
              // 右矢印 - 最大月に達したら非表示
              SizedBox(
                width: 48,
                child: (widget.maxDate != null &&
                        _focusedDay.year == widget.maxDate!.year &&
                        _focusedDay.month == widget.maxDate!.month)
                    ? null // 非表示
                    : IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          setState(() {
                            final newDate = DateTime(
                              _focusedDay.year,
                              _focusedDay.month + 1,
                            );
                            _focusedDay = newDate;
                          });
                        },
                      ),
              ),
            ],
          ),
        ),
        // カレンダー本体
        Expanded(
          child: TableCalendar(
            focusedDay: _focusedDay,
            firstDay: widget.minDate != null 
                ? DateTime(widget.minDate!.year, widget.minDate!.month, 1)
                : DateTime(2017, 1, 1),
            lastDay: widget.maxDate != null
                ? DateTime(widget.maxDate!.year, widget.maxDate!.month + 1, 0) // 月末日
                : DateTime(2050, 12, 31),
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
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
            },
            // Remove the format button
            availableCalendarFormats: const {
              CalendarFormat.month: 'Month',
            },
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              headerMargin: EdgeInsets.zero,
              headerPadding: EdgeInsets.zero,
              leftChevronVisible: false,
              rightChevronVisible: false,
              titleTextFormatter: (date, locale) => '', // タイトルテキストを空にする
            ),
          ),
        ),
      ],
    );
  }

  void _showYearMonthPicker(BuildContext context) {
    int selectedYear = _focusedDay.year;
    int selectedMonth = _focusedDay.month;
    
    // 利用可能な年のリストを作成
    final minYear = widget.minDate?.year ?? 2017;
    final maxYear = widget.maxDate?.year ?? DateTime.now().year;
    final yearCount = maxYear - minYear + 1;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 選択された年に応じて利用可能な月を計算
            int minMonth = 1;
            int maxMonth = 12;
            if (widget.minDate != null && selectedYear == widget.minDate!.year) {
              minMonth = widget.minDate!.month;
            }
            if (widget.maxDate != null && selectedYear == widget.maxDate!.year) {
              maxMonth = widget.maxDate!.month;
            }
            
            // 現在選択されている月が範囲外の場合は調整
            if (selectedMonth < minMonth) {
              selectedMonth = minMonth;
            } else if (selectedMonth > maxMonth) {
              selectedMonth = maxMonth;
            }
            
            return AlertDialog(
              title: const Text('年月を選択'),
              content: SizedBox(
                width: double.maxFinite,
                height: 150, // 高さを300から150に変更
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 年の選択
                    Row(
                      children: [
                        const Text('年: ', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<int>(
                            value: selectedYear,
                            isExpanded: true,
                            items: List.generate(
                              yearCount,
                              (index) => DropdownMenuItem(
                                value: minYear + index,
                                child: Text('${minYear + index}年'),
                              ),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedYear = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16), // 間隔を24から16に変更
                    // 月の選択
                    Row(
                      children: [
                        const Text('月: ', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<int>(
                            value: selectedMonth,
                            isExpanded: true,
                            items: List.generate(
                              maxMonth - minMonth + 1,
                              (index) => DropdownMenuItem(
                                value: minMonth + index,
                                child: Text('${minMonth + index}月'),
                              ),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedMonth = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(selectedYear, selectedMonth);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('選択'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}