import 'package:flutter/material.dart';
import 'utils/database_helper.dart';
import 'widgets/message.dart';
import 'utils/app_config.dart';


class TalkPage extends StatefulWidget {
  const TalkPage({Key? key}) : super(key: key);

  @override
  _TalkPageState createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  final dbHelper = DatabaseHelper();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> messages = [];
  int offset = 0;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMoreMessages();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.offset <= 100 && !isLoading) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!isLoading) {
      setState(() => isLoading = true);
      final List<Map<String, dynamic>> newMessages = await dbHelper.getMessages(offset, 10);
      if (newMessages.isNotEmpty) {
        setState(() {
          messages.insertAll(0, newMessages);
          offset += newMessages.length;
        });
      }
      isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('hoge岸piyoり')),
      body: ListView.separated(
        controller: _scrollController,
        itemCount: messages.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16), // ✅ メッセージ間の余白を10pxにする
        itemBuilder: (context, index) {
          var row = messages[index];
          return Message(
            message: row['text'],
            senderName: row['name'],
            time: row['date'],
            avatarAssetPath: "assets/images/icon.png",
            mediaPath: row['filename'].isNotEmpty 
                ? "${AppConfig.appDocumentsDirectory}/${row['name']}/media/${row['filename']}" 
                : null,
          );
        },
      ),

    );
  }
}
