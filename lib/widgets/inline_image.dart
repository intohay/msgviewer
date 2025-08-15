import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/overlay_manager.dart';

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

  const InlineImage({
    Key? key,
    required this.imagePath,
    required this.thumbnailPath,
    this.isSquare = false,
    this.message,
    this.time,
  }) : super(key: key);

  @override
  State<InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<InlineImage> {
  final OverlayManager _overlayManager = OverlayManager();
  bool _showInfo = true; // オーバーレイの情報表示状態
  Timer? _hideTimer; // 自動非表示用タイマー

  @override
  void dispose() {
    _hideTimer?.cancel();
    // ウィジェットが破棄される際はOverlayManagerが管理
    super.dispose();
  }

  void _showOverlay(BuildContext context, FileImage image) {
    // オーバーレイ表示時は情報を表示
    _showInfo = true;
    
    // 10秒後に自動的に情報を非表示にする
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 10), () {
      // タイマーが発火したらフラグを更新（StatefulBuilderで再描画される）
      _showInfo = false;
    });
    
    final overlayEntry = OverlayEntry(
      builder: (overlayContext) => StatefulBuilder(
        builder: (context, setState) {
          // タイマーで非表示になったら状態を更新
          if (_hideTimer != null && !_hideTimer!.isActive) {
            _showInfo = false;
          }
          
          return GestureDetector(
            onTap: () {
              if (_showInfo) {
                // 情報が表示されている場合は非表示にする
                setState(() {
                  _showInfo = false;
                  _hideTimer?.cancel();
                });
              } else {
                // 情報が非表示の場合は再表示する
                setState(() {
                  _showInfo = true;
                  // 再度タイマーを開始
                  _hideTimer?.cancel();
                  _hideTimer = Timer(const Duration(seconds: 10), () {
                    setState(() {
                      _showInfo = false;
                    });
                  });
                });
              }
            },
            child: Container(
              color: Colors.black,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 1.0,  // 最小スケールを1.0に設定（元のサイズより小さくできない）
                      maxScale: 3.0,  // 最大3倍まで拡大可能
                      boundaryMargin: EdgeInsets.zero,  // 画像を画面外に移動できないようにする
                      constrained: true,  // 画像を制約内に保つ
                      child: Center(
                        child: Image(
                          image: image,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  // 上部の日時表示とナビゲーション
                  if (_showInfo)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.grey.shade900.withOpacity(0.7),
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 15,
                          bottom: 15,
                          left: 20,
                          right: 20,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 中央に日時表示
                            if (widget.time != null)
                              Expanded(
                                child: Text(
                                  DateFormat('yyyy/MM/dd HH:mm').format(widget.time!),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.none,
                                    letterSpacing: 0.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            // 右側の×ボタン
                            GestureDetector(
                              onTap: () {
                                _hideTimer?.cancel();
                                _overlayManager.closeOverlay();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 下部のメッセージ表示
                  if (_showInfo && widget.message != null && widget.message!.isNotEmpty)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        width: double.infinity,
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.3, // 画面の30%まで
                        ),
                        color: Colors.grey.shade900.withOpacity(0.7),
                        child: SingleChildScrollView(
                          child: Container(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom + 20,
                              top: 20,
                              left: 20,
                              right: 20,
                            ),
                            child: Text(
                              widget.message!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                decoration: TextDecoration.none,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.left,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    
    // OverlayManagerを通じて表示
    _overlayManager.showOverlay(context, overlayEntry);
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
      print('InlineImage: File not found at path: $displayPath');
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
            print('InlineImage: Error loading image: $error');
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
            print('InlineImage: Error loading image: $error');
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
          _showOverlay(context, FileImage(fullImage));
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: imageWidget,
      ),
    );
  }
}
