import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'talk_page.dart';
import 'utils/database_helper.dart';
import 'utils/file_utils.dart';
import 'utils/progress_manager.dart';
import 'dart:io';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FileManager fileManager = FileManager(DatabaseHelper());  
  List<Map<String, dynamic>> talkPages = []; // ZIPごとのTalkPageを管理
  final dbHelper = DatabaseHelper(); // アイコンパス取得などに使用


  @override
  void initState() {
    super.initState();
    _loadTalkPages();
  }

  Future<void> _loadTalkPages() async {
    final talks = await dbHelper.getAllTalks();
    final List<Map<String, dynamic>> talksWithScrollIndex = [];
    final directory = await getApplicationDocumentsDirectory();
    
    for (var talk in talks) {
      final scrollIndex = await dbHelper.getScrollIndex(talk['name']);
      debugPrint('HomePage: Loading scroll index $scrollIndex for ${talk['name']}');
      
      // アイコンパスの処理
      String iconPath = 'assets/images/icon.png';
      final savedIconPath = talk['icon_path'] as String?;
      
      if (savedIconPath != null && !savedIconPath.startsWith('assets/')) {
        // 既に絶対パスの場合
        if (savedIconPath.startsWith('/')) {
          // ファイルの存在確認
          if (await File(savedIconPath).exists()) {
            iconPath = savedIconPath;
          }
        } else {
          // 相対パスの場合、絶対パスに変換
          final absolutePath = '${directory.path}/$savedIconPath';
          if (await File(absolutePath).exists()) {
            iconPath = absolutePath;
          }
        }
      } else if (savedIconPath != null) {
        iconPath = savedIconPath; // assets/から始まる場合
      }
      
      talksWithScrollIndex.add({
        'name': talk['name'],
        'iconPath': iconPath,
        'savedState': {
          'scrollIndex': scrollIndex,
        },
      });
    }
    
    setState(() {
      talkPages = talksWithScrollIndex;
    });
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      
      body: Padding(
        padding: const EdgeInsets.all(4.0),
        // GridView.builder を使って円形アイコン+名前を並べる
        child: GridView.builder(
          itemCount: talkPages.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,         // 1行にいくつ表示するか
            mainAxisSpacing: 0,        // 縦方向のスペース
            crossAxisSpacing: 4,       // 横方向のスペース
            childAspectRatio: 0.7,     // 子要素の縦横比（お好みで調整）
          ),
          itemBuilder: (context, index) {
            final talk = talkPages[index];
            return GestureDetector(
              onTap: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TalkPage(
                      name: talk['name'],
                      savedState: talk['savedState'] != null && (talk['savedState'] as Map).isNotEmpty
                          ? Map<String, dynamic>.from(talk['savedState'])
                          : null,
                    ),
                  ),
                );
                if (result != null && result is Map<String, dynamic>) {
                  // 名前が変更された場合の処理
                  if (result['nameChanged'] == true) {
                    setState(() {
                      talkPages[index]['name'] = result['newName'];
                    });
                    // スクロール位置を新しい名前で保存
                    if (result['scrollIndex'] != null) {
                      await dbHelper.setScrollIndex(result['newName'], result['scrollIndex']);
                    }
                  } else {
                    // 通常の処理
                    // スクロール位置をデータベースに保存
                    if (result['scrollIndex'] != null) {
                      debugPrint('HomePage: Saving scroll index ${result['scrollIndex']} for ${talk['name']}');
                      await dbHelper.setScrollIndex(talk['name'], result['scrollIndex']);
                    }
                  }
                  // データベースから最新のスクロール位置を取得
                  final latestScrollIndex = await dbHelper.getScrollIndex(talk['name']);
                  setState(() {
                    // savedStateを更新（データベースのスクロール位置を使用）
                    talkPages[index]['savedState'] = {
                      'messages': result['messages'],
                      'scrollIndex': latestScrollIndex,  // データベースから読み込んだ値を使用
                      'iconPath': result['iconPath'],
                    };
                    talkPages[index]['iconPath'] = result['iconPath'];
                  });
                }
              },
              // 長押しでメニューを表示
              onLongPress: () async {
                final action = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(talk['name'] ?? ''),
                    content: const Text('操作を選択してください'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'edit'),
                        child: const Text('名前を編集'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'delete'),
                        child: const Text('削除'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('キャンセル'),
                      ),
                    ],
                  ),
                );
                
                if (action == 'edit') {
                  // 名前編集ダイアログを表示
                  final TextEditingController nameController = TextEditingController(text: talk['name']);
                  if (!context.mounted) return;
                  final newName = await showDialog<String>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
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
                          onPressed: () => Navigator.pop(dialogContext, null),
                          child: const Text('キャンセル'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, nameController.text),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                  
                  if (newName != null && newName.isNotEmpty && newName != talk['name']) {
                    try {
                      // データベースでトーク名を更新
                      await dbHelper.updateTalkName(talk['name'], newName);
                      // UIを更新
                      if (!context.mounted) return;
                      setState(() {
                        talkPages[index]['name'] = newName;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('トーク名を「$newName」に変更しました')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('名前の変更中にエラーが発生しました: $e')),
                      );
                    }
                  }
                } else if (action == 'delete') {
                  // 削除確認ダイアログを表示
                  if (!context.mounted) return;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('トークの削除'),
                      content: const Text('本当にこのトークを削除しますか？\n(関連するファイルも削除されます)'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('キャンセル'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('削除'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true) {
                    try {
                      // データベース上のレコードおよび関連ファイルを削除する処理
                      await dbHelper.deleteTalk(talk['name']);
                      // ホーム画面から対象のトークを削除
                      if (!context.mounted) return;
                      setState(() {
                        talkPages.removeAt(index);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('トークが削除されました')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('削除中にエラーが発生しました: $e')),
                      );
                    }
                  }
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 円形アイコン部分
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.blue[100], 
                    backgroundImage: (talk['iconPath'] as String).startsWith('assets/')
                        ? AssetImage(talk['iconPath'] as String) as ImageProvider
                        : FileImage(File(talk['iconPath'] as String)),
                  ),
                  const SizedBox(height: 8),
                  // 名前
                  Text(
                    talk['name'] ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _pickAndProcessZip(context);
        },
        tooltip: 'Import Zip File',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// ZIPを選択して処理し、TalkPageを追加する処理
  Future<void> _pickAndProcessZip(BuildContext context) async {
    String? zipFilePath = await fileManager.pickZipFile();
    if (zipFilePath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected.')),
        );
      }
      return;
    }

    // 進捗管理インスタンスを作成
    final progressManager = ProgressManager();
    
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          child: StreamBuilder<ProgressData>(
            stream: progressManager.progressStream,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final progress = data?.progress ?? 0.0;
              final message = data?.message ?? '準備中...';
              final detail = data?.detail;
              
              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    try {
      // ZIPを解凍して処理（進捗管理付き）
      String? name = await fileManager.processZip(zipFilePath, progressManager: progressManager);
      if (name == null) return;

      String iconPath = "assets/images/icon.png";

      await dbHelper.addTalk(name, iconPath);
      
      setState(() {
        talkPages.add({
          'name': name,
          'iconPath': iconPath,
          'savedState': <String, dynamic>{},
        });
      });
    } catch (e) {
      debugPrint("Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      progressManager.dispose();
      if (context.mounted) {
        Navigator.pop(context); 
      }
    }
  }
}