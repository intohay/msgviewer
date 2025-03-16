import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class IconChangePage extends StatefulWidget {
  final String currentIconPath;
  final Function(String) onIconChanged;

  const IconChangePage({Key? key, required this.currentIconPath, required this.onIconChanged}) : super(key: key);

  @override
  _IconChangePageState createState() => _IconChangePageState();
}

class _IconChangePageState extends State<IconChangePage> {
  String? iconPath;

  @override
  void initState() {
    super.initState();
    iconPath = widget.currentIconPath;
  }

  Future<String> _saveImageLocally(String originalPath) async {
    final directory = await getApplicationDocumentsDirectory();
    final localPath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.png';
    final File localFile = File(localPath);
    await File(originalPath).copy(localPath); // コピーして保存
    print("iconPath: $iconPath");
    return localPath;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final savedPath = await _saveImageLocally(pickedFile.path);
      setState(() {
        iconPath = savedPath;
        print("iconPath: $iconPath");
      });
      widget.onIconChanged(savedPath); // アイコン変更を通知
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("アイコンを変更")),
      body: Center( // 画面全体の中央配置
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // 垂直方向に中央
          crossAxisAlignment: CrossAxisAlignment.center, // 水平方向にも中央
          children: [
            CircleAvatar(
              radius: 80, // ✅ アイコンサイズを大きく
              backgroundImage: File(iconPath!).existsSync() 
                  ? FileImage(File(iconPath!)) 
                  : AssetImage(iconPath!) as ImageProvider,
            ),
            const SizedBox(height: 30), // ✅ ボタンとの間隔を広げる
            ElevatedButton(
              onPressed: _pickImage,
              child: const Text("画像を選ぶ"),
            ),
          ],
        ),
      ),
    );
  }
}
