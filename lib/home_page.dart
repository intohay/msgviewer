import 'package:flutter/material.dart';
import 'talk_page.dart';
import 'utils/database_helper.dart';
import 'utils/file_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FileManager fileManager = FileManager(DatabaseHelper());  
  List<Map<String, dynamic>> talkPages = []; // ✅ ZIPごとのTalkPageを管理

 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.builder(
        itemCount: talkPages.length,
        itemBuilder: (context, index) {
          final talk = talkPages[index];
          return ListTile(
            title: Text(talk['name']),
            onTap: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TalkPage(name: talk['name'], savedState: talk['savedState'] != null ? Map<String, dynamic>.from(talk['savedState']) : null),
                ),
              );
              if (result != null && result is Map<String, dynamic>) {
                setState(() {
                  talkPages[index]['savedState'] = result; // ✅ 戻ってきたら状態を保存
                });
              }
            },
          );
        },
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

    String? name = await fileManager.processZip(zipFilePath);

  

    // **新しいTalkPageをリストに追加**
    setState(() {
      talkPages.add({
      'name': name,  // ZIPの拡張子を除いたファイル名をタイトルにする
      'savedState': <String, dynamic>{},      // 初期状態は空
      });
    });
  }
}
