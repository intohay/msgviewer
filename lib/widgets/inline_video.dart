import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';


// tap to show video
class InlineVideo extends StatefulWidget {
  final String videoPath;


  const InlineVideo({Key? key, required this.videoPath}) : super(key: key);

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  OverlayEntry? overlayEntry;

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
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 200,
            ),
            child: Container(
              color: Colors.black,
              child: Center(
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 50,
                ),
              ),
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

  @override
  void initState() {
    super.initState();
    print(widget.videoPath);
    _controller = VideoPlayerController.file(File(widget.videoPath))
    ..initialize().then((_) {
      setState(() {});
    });
  }

 

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
      return Scaffold(
      backgroundColor: Colors.black,
      body: _controller.value.isInitialized
      ? Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            // 動画を表示
            child: VideoPlayer(_controller),
          ),
          Column(
            children: [
              VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.grey,
                  backgroundColor: Colors.white,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: () {
                      // 動画を最初から再生
                      _controller
                          .seekTo(Duration.zero)
                          .then((_) => _controller.play());
                    },
                    icon: Icon(Icons.refresh),
                    color: Colors.white,
                  ),
                  IconButton(
                    onPressed: () {
                      // 動画を再生
                      _controller.play();
                    },
                    icon: Icon(Icons.play_arrow),
                    color: Colors.white,
                  ),
                  IconButton(
                    onPressed: () {
                      // 動画を一時停止
                      _controller.pause();
                    },
                    icon: Icon(Icons.pause),
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ],
      ) : Center(child: CircularProgressIndicator()),
    );
  }
}
