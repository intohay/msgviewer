import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import '../utils/overlay_manager.dart';

// 動画のインライン再生サムネイル
class InlineVideo extends StatefulWidget {
  final String videoPath;
  final String thumbnailPath;

  /// 正方形表示にするかどうか（デフォルト false）
  /// true の場合、中央でクロップして正方形表示
  final bool isSquare;

  /// 再生アイコンを表示するかどうか（デフォルト true）
  final bool showPlayIcon;
  
  /// 日時（オーバーレイ表示用）
  final DateTime? time;

  const InlineVideo({
    Key? key,
    required this.videoPath,
    required this.thumbnailPath,
    this.isSquare = false,
    this.showPlayIcon = true,
    this.time,
  }) : super(key: key);

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  final OverlayManager _overlayManager = OverlayManager();
  String? _thumbnailPath;
  bool _isLoading = true;
  double _aspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    _initializeDisplay();
  }

  @override
  void dispose() {
    // ウィジェットが破棄される際はOverlayManagerが管理
    super.dispose();
  }

  /// サムネイル画像のアスペクト比を取得
  Future<void> _initializeDisplay() async {
    final thumbFile = File(widget.thumbnailPath);
    if (await thumbFile.exists()) {
      try {
        final bytes = await thumbFile.readAsBytes();
        ui.decodeImageFromList(bytes, (ui.Image image) {
          if (mounted) {
            setState(() {
              _aspectRatio = image.width / image.height;
              _thumbnailPath = widget.thumbnailPath;
              _isLoading = false;
            });
          }
        });
      } catch (e) {
        print('InlineVideo: Error loading thumbnail: $e');
        if (mounted) {
          setState(() {
            _thumbnailPath = null;
            _isLoading = false;
          });
        }
      }
    } else {
      // サムネイルがない場合
      print('InlineVideo: Thumbnail not found at: ${widget.thumbnailPath}');
      if (mounted) {
        setState(() {
          _thumbnailPath = null;
          _isLoading = false;
        });
      }
    }
  }

  /// フルスクリーンの動画再生をオーバーレイで表示
  void _showOverlay(BuildContext context, String videoPath) {
    // スワイプ用の変数
    double verticalDragOffset = 0;
    double opacity = 1.0;
    bool showInfo = true; // オーバーレイの情報表示状態
    Timer? hideTimer;
    VideoPlayerController? controller;
    bool isPlaying = false;
    Duration position = Duration.zero;
    Duration duration = Duration.zero;
    
    // 動画コントローラーの初期化
    final videoFile = File(videoPath);
    
    // 10秒後に自動的に情報を非表示にする
    void startHideTimer(Function setState, BuildContext context) {
      hideTimer?.cancel();
      hideTimer = Timer(const Duration(seconds: 10), () {
        if (context.mounted) {
          setState(() {
            showInfo = false;
          });
        }
      });
    }
    
    final overlayEntry = OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // 動画コントローラーの初期化（StatefulBuilder内で一度だけ）
          if (controller == null && videoFile.existsSync()) {
            controller = VideoPlayerController.file(videoFile)
              ..initialize().then((_) {
                if (context.mounted) {
                  setState(() {
                    isPlaying = true;
                    duration = controller!.value.duration;
                  });
                  controller!.play();
                  controller!.setLooping(true);
                  
                  // 位置の更新をリスニング
                  controller!.addListener(() {
                    if (controller!.value.isInitialized && context.mounted) {
                      setState(() {
                        position = controller!.value.position;
                        duration = controller!.value.duration;
                        isPlaying = controller!.value.isPlaying;
                      });
                    }
                  });
                }
              }).catchError((error) {
                print('VideoPlayer: Error initializing video: $error');
              });
          }
          
          // 初回のタイマー開始
          if (hideTimer == null && showInfo) {
            startHideTimer(setState, context);
          }
          
          return GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                verticalDragOffset += details.delta.dy;
                // 下にスワイプした時のみ反応（上スワイプは無視）
                if (verticalDragOffset > 0) {
                  // スワイプ量に応じて透明度を調整
                  opacity = (1.0 - (verticalDragOffset / 300)).clamp(0.0, 1.0);
                } else {
                  verticalDragOffset = 0;
                  opacity = 1.0;
                }
              });
            },
            onVerticalDragEnd: (details) {
              // 100ピクセル以上下にスワイプするか、速度が一定以上なら閉じる
              if (verticalDragOffset > 100 || 
                  (details.primaryVelocity != null && details.primaryVelocity! > 500)) {
                hideTimer?.cancel();
                controller?.dispose();
                _overlayManager.closeOverlay();
              } else {
                // 閉じない場合は元に戻す
                setState(() {
                  verticalDragOffset = 0;
                  opacity = 1.0;
                });
              }
            },
            onTap: () {
              if (showInfo) {
                // 情報が表示されている場合は非表示にする
                setState(() {
                  showInfo = false;
                  hideTimer?.cancel();
                });
              } else {
                // 情報が非表示の場合は再表示する
                setState(() {
                  showInfo = true;
                  // 再度タイマーを開始
                  startHideTimer(setState, context);
                });
              }
            },
            child: Stack(
              children: [
                // 背景（透明度変化）
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  color: Colors.black.withOpacity(opacity),
                ),
                // 動画プレイヤーとUIコントロール（一緒に動く）
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  transform: Matrix4.translationValues(0, verticalDragOffset, 0),
                  child: Stack(
                    children: <Widget>[
                      // 動画プレイヤー本体
                      Positioned.fill(
                        child: controller != null && controller!.value.isInitialized
                            ? Center(
                                child: AspectRatio(
                                  aspectRatio: controller!.value.aspectRatio,
                                  child: VideoPlayer(controller!),
                                ),
                              )
                            : const Center(child: CircularProgressIndicator()),
                      ),
                      // 上部の日時表示とナビゲーション
                      if (showInfo)
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
                                    hideTimer?.cancel();
                                    controller?.dispose();
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
                      // 中央の再生コントロール
                      if (showInfo && controller != null && controller!.value.isInitialized)
                        Positioned.fill(
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 5秒巻き戻し
                                GestureDetector(
                                  onTap: () {
                                    final newPosition = position - const Duration(seconds: 5);
                                    controller!.seekTo(newPosition);
                                    startHideTimer(setState, context); // タイマーリセット
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.replay_5,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 30),
                                // 再生/一時停止
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isPlaying) {
                                        controller!.pause();
                                      } else {
                                        controller!.play();
                                      }
                                    });
                                    startHideTimer(setState, context); // タイマーリセット
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 50,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 30),
                                // 5秒早送り
                                GestureDetector(
                                  onTap: () {
                                    final newPosition = position + const Duration(seconds: 5);
                                    controller!.seekTo(newPosition);
                                    startHideTimer(setState, context); // タイマーリセット
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.forward_5,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // 下部のシークバーと時間表示
                      if (showInfo && controller != null && controller!.value.isInitialized)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.grey.shade900.withOpacity(0.7),
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom + 20,
                              top: 20,
                              left: 20,
                              right: 20,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // プログレスバー
                                VideoProgressIndicator(
                                  controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.white,
                                    bufferedColor: Colors.grey,
                                    backgroundColor: Colors.black26,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // 時間表示
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    // OverlayManagerを通じて表示
    _overlayManager.showOverlay(context, overlayEntry);
  }
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    // 再生アイコン
    Widget playIcon = const Center(
      child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50),
    );
    if (!widget.showPlayIcon) {
      playIcon = const SizedBox.shrink();
    }

    // サムネイル
    Widget thumbnailWidget;
    if (_isLoading) {
      thumbnailWidget = const Center(child: CircularProgressIndicator());
    } else if (_thumbnailPath != null && _thumbnailPath!.isNotEmpty) {
      // 正方形の場合は中央クロップ (BoxFit.cover)
      // そうでない場合は従来通り (BoxFit.contain)
      final boxFit = widget.isSquare ? BoxFit.cover : BoxFit.contain;
      thumbnailWidget = Image.file(
        File(_thumbnailPath!),
        fit: boxFit,
        errorBuilder: (context, error, stackTrace) {
          print('InlineVideo: Error displaying thumbnail: $error');
          return Container(
            color: Colors.grey[800],
            child: const Center(
              child: Icon(Icons.videocam_off, size: 48, color: Colors.grey),
            ),
          );
        },
      );
    } else {
      // サムネイルが無い場合は黒背景
      thumbnailWidget = Container(
        color: Colors.grey[800],
        child: const Center(
          child: Icon(Icons.videocam_off, size: 48, color: Colors.grey),
        ),
      );
    }

    // 正方形表示 or 従来の高さ250px表示
    Widget displayedWidget;
    if (widget.isSquare) {
      // ★ 正方形 + BoxFit.cover
      displayedWidget = AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumbnailWidget,
            playIcon,
          ],
        ),
      );
    } else {
      // ★ 従来の表示
      displayedWidget = LayoutBuilder(builder: (context, constraints) {
        const double fixedHeight = 250.0;
        final double calculatedWidth = fixedHeight * _aspectRatio;
        final double maxWidth = constraints.maxWidth;

        return Center(
          child: Container(
            height: fixedHeight,
            width: calculatedWidth > maxWidth ? maxWidth : calculatedWidth,
            child: Stack(
              fit: StackFit.expand,
              children: [
                thumbnailWidget,
                playIcon,
              ],
            ),
          ),
        );
      });
    }

    return GestureDetector(
      onTap: () {
        // ビデオファイルが存在するかチェック
        final videoFile = File(widget.videoPath);
        if (!videoFile.existsSync()) {
          print('InlineVideo: Video file not found at: ${widget.videoPath}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('動画ファイルが見つかりません')),
          );
          return;
        }
        // フルスクリーン再生をオーバーレイ表示
        _showOverlay(context, widget.videoPath);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: displayedWidget,
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String videoPath;

  const VideoPlayerPage({Key? key, required this.videoPath}) : super(key: key);

  @override
  _VideoPlayerPageState createState() => _VideoPlayerPageState();
}

/// フルスクリーン動画再生ページ
class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _showOverlay = false;
  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    final videoFile = File(widget.videoPath);
    if (!videoFile.existsSync()) {
      print('VideoPlayerPage: Video file not found at: ${widget.videoPath}');
      return;
    }
    _controller = VideoPlayerController.file(videoFile)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
          _controller.setLooping(true);
        }
      }).catchError((error) {
        print('VideoPlayerPage: Error initializing video: $error');
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _overlayTimer?.cancel();
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
      if (_showOverlay) {
        _startOverlayTimer();
      } else {
        _overlayTimer?.cancel();
      }
    });
  }

  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showOverlay = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          children: [
            Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            if (_showOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Stack(
                    children: [
                      // 中央の再生・巻戻し・早送り
                      Align(
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_5, color: Colors.white, size: 40),
                              onPressed: () {
                                _controller.seekTo(
                                  _controller.value.position - const Duration(seconds: 5),
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 50,
                              ),
                              onPressed: () {
                                setState(() {
                                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                                });
                                _startOverlayTimer();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_5, color: Colors.white, size: 40),
                              onPressed: () {
                                _controller.seekTo(
                                  _controller.value.position + const Duration(seconds: 5),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // 下部シークバー
                      Positioned(
                        bottom: 80,
                        left: 16,
                        right: 16,
                        child: Column(
                          children: [
                            VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.white,
                                bufferedColor: Colors.grey,
                                backgroundColor: Colors.black,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_controller.value.position),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Text(
                                  _formatDuration(_controller.value.duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
