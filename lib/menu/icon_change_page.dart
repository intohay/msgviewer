import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/database_helper.dart';



class IconChangePage extends StatefulWidget {
  final String talkName;
  final String currentIconPath;
  final Function(String) onIconChanged;

  const IconChangePage({super.key, required this.talkName, required this.currentIconPath, required this.onIconChanged});

  @override
  IconChangePageState createState() => IconChangePageState();
}

class IconChangePageState extends State<IconChangePage> {
  String? iconPath;

  @override
  void initState() {
    super.initState();
    iconPath = widget.currentIconPath;
  }

  Future<String> _saveImageLocally(String originalPath) async {
    final directory = await getApplicationDocumentsDirectory();
    // 相対パスで保存（トーク名/icons/タイムスタンプ.png）
    final relativePath = '${widget.talkName}/icons/${DateTime.now().millisecondsSinceEpoch}.png';
    final localPath = '${directory.path}/$relativePath';
    
    // ディレクトリが存在しない場合は作成
    final File localFile = File(localPath);
    await localFile.parent.create(recursive: true);
    
    await File(originalPath).copy(localPath); // コピーして保存
    debugPrint("Saved icon to relative path: $relativePath");
    return relativePath; // 相対パスを返す
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      // 画像をクロップ
      final croppedFile = await _cropImage(pickedFile.path);
      
      if (croppedFile != null) {
        final savedRelativePath = await _saveImageLocally(croppedFile.path);
        await DatabaseHelper().setIconPath(widget.talkName, savedRelativePath);
        
        // UIには絶対パスを設定
        final directory = await getApplicationDocumentsDirectory();
        final absolutePath = '${directory.path}/$savedRelativePath';
        
        setState(() {
          iconPath = absolutePath;
          debugPrint("iconPath: $iconPath");
        });
        widget.onIconChanged(absolutePath); // 絶対パスで通知
      }
    }
  }

  Future<CroppedFile?> _cropImage(String imagePath) async {
    return await ImageCropper().cropImage(
      sourcePath: imagePath,
      cropStyle: CropStyle.circle,  // 円形でクロップ
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),  // 正方形の比率
      aspectRatioPresets: [
        CropAspectRatioPreset.square,  // 正方形のみ
      ],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'アイコンを調整',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,  // アスペクト比を固定
          hideBottomControls: false,
          showCropGrid: true,
        ),
        IOSUiSettings(
          title: 'アイコンを調整',
          aspectRatioLockEnabled: true,  // アスペクト比を固定
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,  // アスペクト比選択ボタンを非表示
          rotateButtonsHidden: false,
          resetButtonHidden: false,
          doneButtonTitle: '完了',
          cancelButtonTitle: 'キャンセル',
        ),
      ],
    );
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
