import 'package:flutter/material.dart';
import '../utils/database_helper.dart';
import '../widgets/message.dart';
import '../utils/helper.dart';

class FavoritesPage extends StatefulWidget {
  final String name;
  final String iconPath;
  final String callMeName;

  const FavoritesPage({
    Key? key,
    required this.name,
    required this.iconPath,
    required this.callMeName,
  }) : super(key: key);

  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
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

          return Message(
            message: replacePlaceHolders(row['text'], widget.callMeName),
            senderName: row['name'],
            time: DateTime.parse(row['date']),
            avatarAssetPath: widget.iconPath,
            mediaPath: row['filepath'],
            thumbPath: row['thumb_filepath'],
            isFavorite: isFavorite,
          );
        },
      ),
    );
  }
}
