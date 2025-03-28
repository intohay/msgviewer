import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// 動画のインライン再生サムネイル
class InlineVideo extends StatefulWidget {
  final String videoPath;
  final String thumbnailPath;

  /// 正方形表示にするかどうか（デフォルト false）
  /// true の場合、中央でクロップして正方形表示
  final bool isSquare;

  /// 再生アイコンを表示するかどうか（デフォルト true）
  final bool showPlayIcon;

  const InlineVideo({
    Key? key,
    required this.videoPath,
    required this.thumbnailPath,
    this.isSquare = false,
    this.showPlayIcon = true,
  }) : super(key: key);

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  OverlayEntry? overlayEntry;
  String? _thumbnailPath;
  bool _isLoading = true;
  double _aspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    _initializeDisplay();
  }

  /// サムネイル画像のアスペクト比を取得
  Future<void> _initializeDisplay() async {
    final thumbFile = File(widget.thumbnailPath);
    if (await thumbFile.exists()) {
      final bytes = await thumbFile.readAsBytes();
      ui.decodeImageFromList(bytes, (ui.Image image) {
        setState(() {
          _aspectRatio = image.width / image.height;
          _thumbnailPath = widget.thumbnailPath;
          _isLoading = false;
        });
      });
    } else {
      // サムネイルがない場合
      setState(() {
        _thumbnailPath = widget.thumbnailPath;
        _isLoading = false;
      });
    }
  }

  /// フルスクリーンの動画再生をオーバーレイで表示
  void _showOverlay(BuildContext context, Widget videoPlayer) {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Material(
          color: Colors.black,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: videoPlayer),
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
      thumbnailWidget = Image.file(File(_thumbnailPath!), fit: boxFit);
    } else {
      // サムネイルが無い場合は黒背景
      thumbnailWidget = Container(color: Colors.black);
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
        // フルスクリーン再生をオーバーレイ表示
        _showOverlay(context, VideoPlayerPage(videoPath: widget.videoPath));
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
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
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
