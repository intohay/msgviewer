import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class InlineImage extends StatefulWidget {
  final String imagePath;
  final String thumbnailPath;

  /// 正方形表示にするかどうか（デフォルトは false で従来通り）
  /// true の場合、中央でクロップして正方形表示
  final bool isSquare;

  const InlineImage({
    Key? key,
    required this.imagePath,
    required this.thumbnailPath,
    this.isSquare = false,
  }) : super(key: key);

  @override
  State<InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<InlineImage> {
  OverlayEntry? overlayEntry;

  void _showOverlay(BuildContext context, FileImage image) {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Material(
          color: Colors.black,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: PhotoView(
                  imageProvider: image,
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.5,
                  maxScale: PhotoViewComputedScale.covered * 3.0,
                  initialScale: PhotoViewComputedScale.contained,
                ),
              ),
              Positioned(
                top: 40,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 30, color: Colors.white),
                  onPressed: () => overlayEntry?.remove(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    // 実際に表示するサムネイル（デフォルトは thumbnailPath、なければ imagePath）
    final displayPath = widget.thumbnailPath.isNotEmpty ? widget.thumbnailPath : widget.imagePath;

    // タップで拡大表示する用の画像
    final fullImage = File(widget.imagePath);

    // 画像本体
    Widget imageWidget;
    if (widget.isSquare) {
      // ★ 正方形表示 & クロップ（BoxFit.cover）
      imageWidget = AspectRatio(
        aspectRatio: 1.0, // 正方形
        child: Image.file(
          File(displayPath),
          fit: BoxFit.cover, // 埋め尽くしてはみ出した部分をクロップ
        ),
      );
    } else {
      // ★ 従来の表示
      imageWidget = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Image.file(
          File(displayPath),
          fit: BoxFit.contain,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        _showOverlay(context, FileImage(fullImage));
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: imageWidget,
      ),
    );
  }
}
