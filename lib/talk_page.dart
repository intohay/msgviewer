import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'utils/database_helper.dart';
import 'widgets/message.dart';
import 'utils/app_config.dart';
import 'settings/icon_change_page.dart';
import 'settings/call_me_page.dart';


class TalkPage extends StatefulWidget {
  final Map<String, dynamic>? savedState;
  final String? name;
  

  const TalkPage({Key? key, required this.name, this.savedState}) : super(key: key);

  @override
  _TalkPageState createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  final dbHelper = DatabaseHelper();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> messages = [];
  int offset = 0;
  bool isLoading = false;
  String? iconPath;
  String? callMeName;

  @override
  void initState() {
    super.initState();
    _loadIcon();
    _loadCallMeName();
    if (widget.savedState?["messages"]?.isNotEmpty ?? false) {
      messages = widget.savedState!['messages'] ?? [];
      offset = widget.savedState!['offset'] ?? messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.savedState!['scrollOffset'] != null) {
          _scrollController.jumpTo(widget.savedState!['scrollOffset']);
        }
      });
    } else {
      _loadMoreMessages();
    }
    
    _scrollController.addListener(_scrollListener);
  }

  


  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 100 && !isLoading) {
      _loadMoreMessages();
    }
  }

  void _handlePop() {
    final stateToSave = {
      'messages': messages,
      'scrollOffset': _scrollController.offset,
      'offset': offset,
    };
    Navigator.pop(context, stateToSave);
  }

  Future<void> _loadCallMeName() async {
    final name = await dbHelper.getCallMeName(widget.name ?? '');
    setState(() {
      callMeName = name ?? "あなた";
    });
  }

  Future<void> _loadMoreMessages() async {
    if (isLoading) return;

    setState(() => isLoading = true);
    


    final List<Map<String, dynamic>> newMessages = await dbHelper.getMessages(widget.name, offset, 10);
    print("newMessages length: ${newMessages.length}");

    if (newMessages.isNotEmpty) {
      setState(() {
        // newMessagesをreverseして追加する
        messages.addAll(newMessages); 
        // messages.sort((a, b) => b['date'].compareTo(a['date'])); // ✅ 日付順にソート
        offset += newMessages.length;
      });

    }

    setState(() => isLoading = false);
  }

  /// **メニューを開く**
  void _openSettingsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 30.0), // ⬅ ここで下側に余白を追加
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

  Future<void> _loadIcon() async {
    final path = await dbHelper.getIconPath(widget.name ?? '');
    setState(() {
      iconPath = path ?? "assets/images/icon.png";
    });
  }

  void _onMenuTap(String action) {
    Navigator.pop(context);

    if (action == "Icon") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IconChangePage(
            currentIconPath: iconPath!,
            onIconChanged: (newPath) async {
              await dbHelper.setIconPath(widget.name ?? '', newPath);
              _loadIcon();
            }
          ),
        ),
      );
    } else if (action == "Call me") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallMePage(
            name: widget.name!,
            currentCallMe: callMeName,
            onCallMeChanged: (newName) {
              setState(() {
                callMeName = newName;
              });
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$action tapped")));
    }
    
  }

  String _replacePlaceHolders(String text) {
    String modifiedText = text.replaceAll("%%%", callMeName ?? "あなた").replaceAll("％％％", callMeName ?? "あなた");

    return modifiedText;
  }

  Widget _buildMenuItem(IconData icon, String text,  VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(text),
      onTap: onTap,
    );
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
            icon: Icon(Icons.more_horiz),
            onPressed: _openSettingsMenu,
          ),
        ],
      ),
      body: ListView.separated(
        key: const PageStorageKey<String>('talkPageScrollKey'),
        controller: _scrollController,
        reverse: true,
        itemCount: messages.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          var row = messages[index];
          return Message(
            message: _replacePlaceHolders(row['text']).trim(),
            senderName: row['name'],
            time: DateTime.parse(row['date']),  // Fixed DateTimerow to DateTime.parse(row['date']),
            avatarAssetPath: iconPath ?? "assets/images/icon.png",
            mediaPath: row['filename'].isNotEmpty 
                ? "${AppConfig.appDocumentsDirectory}/${row['name']}/media/${row['filename']}" 
                : null,
          );
        },
      ),
    );
  }
}
