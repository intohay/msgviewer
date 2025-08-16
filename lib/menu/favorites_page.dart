import 'package:flutter/material.dart';
import '../utils/database_helper.dart';
import '../widgets/message.dart';
import '../utils/helper.dart';

class FavoritesPage extends StatefulWidget {
  final String name;
  final String iconPath;
  final String callMeName;

  const FavoritesPage({
    super.key,
    required this.name,
    required this.iconPath,
    required this.callMeName,
  });

  @override
  FavoritesPageState createState() => FavoritesPageState();
}

class FavoritesPageState extends State<FavoritesPage> {
  final dbHelper = DatabaseHelper();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> favoriteMessages = [];
  int offset = 0;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // スクロールリスナーを追加
    _scrollController.addListener(_scrollListener);
    // 初回ロード
    _loadMoreFavoriteMessages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// スクロール監視
  void _scrollListener() {
    // ListView が reverse:true の場合、"上" が maxScrollExtent になる
    // offset が maxScrollExtent - 100 以上なら、そろそろトップなので追加読み込み
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 100 && !isLoading) {
      _loadMoreFavoriteMessages();
    }
  }

  /// 「is_favorite = 1」のメッセージを部分的に取得
  Future<void> _loadMoreFavoriteMessages() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    // DBから次の10件を取得
    final rawList = await dbHelper.getFavoriteMessages(widget.name, offset, 10);
    final List<Map<String, dynamic>> newMessages =
        rawList.map((row) => Map<String, dynamic>.from(row)).toList();

    if (newMessages.isNotEmpty) {
      setState(() {
        favoriteMessages.addAll(newMessages);
        offset += newMessages.length;
      });
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.name} のお気に入り"),
      ),
      body: ListView.builder(
        controller: _scrollController,
        reverse: true,              // 最新が下に来るようにする
        itemCount: favoriteMessages.length,
        itemBuilder: (context, index) {
          final row = favoriteMessages[index];
          final bool isFavorite = (row['is_favorite'] == 1);
          
          // お気に入りメッセージの中でメディアファイルを持つものだけを抽出（逆順で）
          final allMediaMessages = favoriteMessages.where((msg) {
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

          return Message(
            message: replacePlaceHolders(row['text'], widget.callMeName),
            senderName: row['name'],
            time: DateTime.parse(row['date']),
            avatarAssetPath: widget.iconPath,
            mediaPath: row['filepath'],
            thumbPath: row['thumb_filepath'],
            isFavorite: isFavorite,
            allMedia: currentMediaIndex != null ? allMediaMessages : null,
            currentMediaIndex: currentMediaIndex,
            callMeName: widget.callMeName,
          );
        },
      ),
      floatingActionButton: favoriteMessages.isNotEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 最上部へジャンプボタン
                FloatingActionButton.small(
                  heroTag: "toTop",
                  onPressed: () {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: const Icon(Icons.arrow_upward),
                ),
                const SizedBox(height: 8),
                // 最下部へジャンプボタン
                FloatingActionButton.small(
                  heroTag: "toBottom",
                  onPressed: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: const Icon(Icons.arrow_downward),
                ),
              ],
            )
          : null,
    );
  }
}
