import 'package:flutter/material.dart';
import 'talk_page.dart';
import 'utils/database_helper.dart';
import 'utils/file_utils.dart';
import 'dart:io';


class HomePage extends StatefulWidget {
  const HomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FileManager fileManager = FileManager(DatabaseHelper());  
  List<Map<String, dynamic>> talkPages = []; // ZIPごとのTalkPageを管理
  final dbHelper = DatabaseHelper(); // アイコンパス取得要

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      
      body: Padding(
        padding: const EdgeInsets.all(4.0),
        // ★ GridView.builder を使って円形アイコン+名前を並べる
        child: GridView.builder(
          itemCount: talkPages.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,         // 1行にいくつ表示するか
            mainAxisSpacing: 0,       // 縦方向のスペース
            crossAxisSpacing: 4,      // 横方向のスペース
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
                      savedState: talk['savedState'] != null
                          ? Map<String, dynamic>.from(talk['savedState'])
                          : null,
                    ),
                  ),
                );
                if (result != null && result is Map<String, dynamic>) {
                  setState(() {
                    talkPages[index]['savedState'] = result; 

                    talkPages[index]['iconPath'] = result['iconPath'];
                  });
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ★ 円形アイコン部分
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.blue[100], 
                    // ここで画像を設定したい場合は backgroundImage を使用
                    backgroundImage: (talk['iconPath'] as String).startsWith('assets/')
                        ? AssetImage(talk['iconPath'] as String) as ImageProvider
                        : FileImage(File(talk['iconPath'] as String)),
                    ),
                  const SizedBox(height: 8),
                  // ★ 名前
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

  /// **ZIPを選択して処理し、TalkPageを追加**
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );


    try {
      // ★ 2) ZIPを解凍して処理
      String? name = await fileManager.processZip(zipFilePath);
      if (name == null) return;

      String? iconPath = await dbHelper.getIconPath(name);
      iconPath ??= "assets/images/icon.png"; // アイコンパスが未設定の場合はデフォルトアイコンを設定

      setState(() {
        talkPages.add({
          'name': name,
          'iconPath': iconPath,
          'savedState': <String, dynamic>{},
        });
      });
    } catch (e) {
      // エラー表示など
      print("Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      // ★ 3) ローディング非表示
      if (context.mounted) {
        Navigator.pop(context); 
      }
    }
  }
}