import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/overlay_manager.dart';
import 'media_viewer_overlay.dart';

class InlineImage extends StatefulWidget {
  final String imagePath;
  final String thumbnailPath;

  /// 正方形表示にするかどうか（デフォルトは false で従来通り）
  /// true の場合、中央でクロップして正方形表示
  final bool isSquare;
  
  /// メッセージテキスト（オーバーレイ表示用）
  final String? message;
  
  /// 日時（オーバーレイ表示用）
  final DateTime? time;
  
  /// 全メディアリスト（スワイプでの切り替え用）
  final List<Map<String, dynamic>>? allMedia;
  
  /// 現在のメディアのインデックス
  final int? currentIndex;
  
  /// トーク名（トーク画面へのジャンプ用）
  final String? talkName;

  const InlineImage({
    super.key,
    required this.imagePath,
    required this.thumbnailPath,
    this.isSquare = false,
    this.message,
    this.time,
    this.allMedia,
    this.currentIndex,
    this.talkName,
  });

  @override
  State<InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<InlineImage> {
  final OverlayManager _overlayManager = OverlayManager();

  @override
  void dispose() {
    super.dispose();
  }

  void _showOverlay(BuildContext context) {
    // allMediaがない場合は現在の画像のみのリストを作成
    final List<Map<String, dynamic>> mediaList;
    final int initialIndex;
    
    if (widget.allMedia != null && widget.allMedia!.isNotEmpty) {
      mediaList = widget.allMedia!;
      initialIndex = widget.currentIndex ?? 0;
    } else {
      // 単体の画像を表示する場合
      mediaList = [{
        'filepath': widget.imagePath,
        'thumb_filepath': widget.thumbnailPath,
        'text': widget.message,
        'date': widget.time?.toIso8601String(),
      }];
      initialIndex = 0;
    }
    
    MediaViewerOverlay.show(
      context: context,
      allMedia: mediaList,
      initialIndex: initialIndex,
      overlayManager: _overlayManager,
      talkName: widget.talkName,
    );
  }
    
  @override
  Widget build(BuildContext context) {
    // 実際に表示するサムネイル（デフォルトは thumbnailPath、なければ imagePath）
    final displayPath = widget.thumbnailPath.isNotEmpty ? widget.thumbnailPath : widget.imagePath;

    // タップで拡大表示する用の画像
    final fullImage = File(widget.imagePath);
    
    // ファイルが存在するかチェック
    final displayFile = File(displayPath);
    if (!displayFile.existsSync()) {
      return Container(
        height: 100,
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      );
    }

    // 画像本体
    Widget imageWidget;
    if (widget.isSquare) {
      // ★ 正方形表示 & クロップ（BoxFit.cover）
      imageWidget = AspectRatio(
        aspectRatio: 1.0, // 正方形
        child: Image.file(
          displayFile,
          fit: BoxFit.cover, // 埋め尽くしてはみ出した部分をクロップ
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
            );
          },
        ),
      );
    } else {
      // ★ 従来の表示
      imageWidget = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Image.file(
          displayFile,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 100,
              color: Colors.grey[300],
              child: const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
            );
          },
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (fullImage.existsSync()) {
          _showOverlay(context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: imageWidget,
      ),
    );
  }
}