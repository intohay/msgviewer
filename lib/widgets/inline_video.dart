import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
// tap to show video
class InlineVideo extends StatefulWidget {
  final String videoPath;


  const InlineVideo({Key? key, required this.videoPath}) : super(key: key);

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
    _initializeThumbnail();
  }



  Future<void> _initializeThumbnail() async {
    final directory = await getTemporaryDirectory();

    final controller = VideoPlayerController.file(File(widget.videoPath));
    await controller.initialize();
    final aspectRatio = controller.value.aspectRatio;
    controller.dispose();


    final thumbnailPath = await VideoThumbnail.thumbnailFile(
      video: widget.videoPath,
      thumbnailPath: "${directory.path}/thumb_${widget.videoPath.hashCode}.jpg",
      imageFormat: ImageFormat.JPEG,
      maxHeight: 400,
      quality: 75,
    );

    if (!mounted) return;


    setState(() {
      _thumbnailPath = thumbnailPath;
      _aspectRatio = aspectRatio;
      _isLoading = false;
    });
  }

  void _showOverlay(BuildContext context, Widget videoPlayer) {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.black,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child:  videoPlayer
              ),
              Positioned(
                top: 40,
                left: 10,
                child: IconButton(
                  icon: Icon(Icons.close, size: 30, color: Colors.white),
                  onPressed: () => overlayEntry?.remove(),
                )
              )
            ]
          )
        )
      )
    );
    Overlay.of(context).insert(overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          _showOverlay(context, VideoPlayerPage(videoPath: widget.videoPath));
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: LayoutBuilder( // ← 追加: 画面幅に合わせて調整
              builder: (context, constraints) {
                double fixedHeight = 250.0; // ← 高さを固定
                double calculatedWidth = fixedHeight * _aspectRatio; // ← 幅を比率で計算
                double maxWidth = constraints.maxWidth; // 親の最大幅

                return Center(
                  child: Container(
                    height: fixedHeight, // 高さを固定
                    width: calculatedWidth > maxWidth ? maxWidth : calculatedWidth, // 最大幅を超えないように調整
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_thumbnailPath != null)
                          Image.file(
                            File(_thumbnailPath!), 
                            fit: BoxFit.contain, // ← 画像をクロップせずに比率を保持
                            width: calculatedWidth,
                            height: fixedHeight,
                          )
                        else if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          Container(color: Colors.black),

                        const Center(
                          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

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

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _showOverlay = false;
  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    print(widget.videoPath);

    _controller = VideoPlayerController.file(File(widget.videoPath))
    ..initialize().then((_) {
      setState(() {});

      // 初期化完了時に動画を再生
      _controller.play();
      _controller.setLooping(true);
      // _controller.addListener(_checkVideoEnd);
    });
  }

 
  // void _checkVideoEnd() {
  //   if (_controller.value.position >= _controller.value.duration) {
  //     _controller.pause();
  //     _controller.seekTo(_controller.value.duration);
  //   }
  // }



  @override
  void dispose() {
    // _controller.removeListener(_checkVideoEnd);
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        
      ),
      body: GestureDetector(
        onTap: _toggleOverlay, // ✅ タップでオーバーレイを表示/非表示
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

            // ✅ タップで表示/非表示のオーバーレイ
            if (_showOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3), // ✅ 半透明のオーバーレイ
                  child: Stack( // ← ✅ ここを Stack に変更
                    children: [
                      // ✅ 再生・巻き戻し・進むボタン
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
                                _startOverlayTimer(); // ✅ ボタン操作後もオーバーレイを自動で消す
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

                      // ✅ シークバーを少し上に移動
                      Positioned(
                        bottom: 80, // ✅ 以前より上に配置
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
                                  _formatDuration(_controller.value.position), // ✅ 再生中も時間を更新
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
