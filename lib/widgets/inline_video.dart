import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

// tap to show video
class InlineVideo extends StatefulWidget {
  final String videoPath;
  final String thumbnailPath;

  const InlineVideo({
    Key? key,
    required this.videoPath,
    required this.thumbnailPath,
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

  Future<void> _initializeDisplay() async {
    // サムネイル画像からアスペクト比を取得
    final thumbFile = File(widget.thumbnailPath);
    if (await thumbFile.exists()) {
      final bytes = await thumbFile.readAsBytes();
      // decodeImageFromList は非同期でコールバックを呼び出す
      ui.decodeImageFromList(bytes, (ui.Image image) {
        setState(() {
          _aspectRatio = image.width / image.height;
          _thumbnailPath = widget.thumbnailPath;
          _isLoading = false;
        });
      });
    } else {
      // 万が一サムネイルが存在しない場合はそのパスをそのまま利用
      setState(() {
        _thumbnailPath = widget.thumbnailPath;
        _isLoading = false;
      });
    }
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
              Positioned.fill(child: videoPlayer),
              Positioned(
                top: 40,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 30, color: Colors.white),
                  onPressed: () => overlayEntry?.remove(),
                ),
              )
            ],
          ),
        ),
      ),
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
        child: LayoutBuilder(builder: (context, constraints) {
          double fixedHeight = 250.0;
          double calculatedWidth = fixedHeight * _aspectRatio;
          double maxWidth = constraints.maxWidth;
          return Center(
            child: Container(
              height: fixedHeight,
              width: calculatedWidth > maxWidth ? maxWidth : calculatedWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!_isLoading && _thumbnailPath != null)
                    Image.file(
                      File(_thumbnailPath!),
                      fit: BoxFit.contain,
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
        }),
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
