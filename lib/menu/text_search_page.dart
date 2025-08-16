// text_search_page.dart (例)
// 適宜ファイル分割してもOK。TalkPageと同じファイル内でも構いません。

import 'package:flutter/material.dart';
import '../utils/database_helper.dart';
import '../widgets/message.dart';  // Message ウィジェットのパスを合わせてください
import '../utils/helper.dart';    // replacePlaceHoldersなどを使う場合

class TextSearchPage extends StatefulWidget {
  final String? name;        // 誰とのトークか (DB検索用)
  final String iconPath;     // アイコンパス
  final String callMeName;   // 置換用の「呼ばれたい名前」

  const TextSearchPage({
    super.key,
    required this.name,
    required this.iconPath,
    required this.callMeName,
  });

  @override
  State<TextSearchPage> createState() => _TextSearchPageState();
}

class _TextSearchPageState extends State<TextSearchPage> {
  final _dbHelper = DatabaseHelper();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];

  // 検索実行
  Future<void> _search() async {
    final queryText = _searchController.text.trim();
    if (queryText.isEmpty) {
      setState(() => _searchResults.clear());
      return;
    }

    setState(() => _isLoading = true);

    // DBから検索 (部分一致)
    final results = await _dbHelper.searchMessagesByText(widget.name, queryText);

    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('テキスト検索'),
      ),
      body: Column(
        children: [
          // 検索フォーム
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // 検索文字列入力
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: '検索文字列',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 検索ボタン
                ElevatedButton(
                  onPressed: _search,
                  child: const Text('検索'),
                ),
              ],
            ),
          ),

          // 件数表示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('件数: ${_searchResults.length}'),
            ),
          ),

          // 検索結果リスト
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final row = _searchResults[index];
                      final isFavorite = (row['is_favorite'] == 1);

                      // 文字列を「あなた」等に置換する例
                      final replacedText = replacePlaceHolders(
                        row['text'],
                        widget.callMeName,
                      ).trim();

                      return Container(
                        // ジャンプボタンが隠れないように最小高さを確保
                        constraints: const BoxConstraints(
                          minHeight: 100, // アイコン(50) + ボタン位置(65) + ボタンサイズ(約28) を考慮
                        ),
                        child: Stack(
                          children: [
                            Message(
                              message: replacedText,
                              senderName: row['name'],
                              time: DateTime.parse(row['date']),
                              avatarAssetPath: widget.iconPath,
                              mediaPath: row['filepath'],
                              thumbPath: row['thumb_filepath'],
                              isFavorite: isFavorite,
                              // ★ ここがポイント：検索キーワードを渡す
                              highlightQuery: _searchController.text.trim(),
                            ),
                            // アイコンの下にジャンプボタンを配置
                            Positioned(
                              left: 16,  // アイコンの左端に揃える
                              top: 65,  // アイコンの下に移動
                              child: GestureDetector(
                                onTap: () {
                                  // ボタンをタップしたら、その日時をTalkPageに渡して戻る
                                  Navigator.of(context).pop({
                                    'jumpToDate': DateTime.parse(row['date']),
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.open_in_new,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _searchResults.isNotEmpty
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
