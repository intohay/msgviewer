import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';


class InlineAudio extends StatefulWidget {
  final String audioPath;

  const InlineAudio({Key? key, required this.audioPath}) : super(key: key);

  @override
  State<InlineAudio> createState() => _InlineAudioState();
}

class _InlineAudioState extends State<InlineAudio> {
  OverlayEntry? overlayEntry;

  void _showOverlay(BuildContext context, Widget audioPlayer) {
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
                child: audioPlayer
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
          _showOverlay(context, AudioPlayerPage(audioPath: widget.audioPath));
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


class AudioPlayerPage extends StatefulWidget {
  final String audioPath;

  const AudioPlayerPage({Key? key, required this.audioPath}) : super(key: key);
  @override
  _AudioPlayerPageState createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.audioPath));
    _controller.initialize().then((_) {
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
    return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VideoProgressIndicator(
            _controller,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor: Colors.purple,
              bufferedColor: Colors.grey,
              backgroundColor: Colors.white,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () {
                  _controller
                      .seekTo(Duration.zero)
                      .then((_) => _controller.play());
                },
                icon: Icon(Icons.refresh),
                color: Colors.grey,
              ),
              IconButton(
                onPressed: () {
                  _controller.play();
                },
                icon: Icon(Icons.play_arrow),
                color: Colors.grey,
              ),
              IconButton(
                onPressed: () {
                  _controller.pause();
                },
                icon: Icon(Icons.pause),
                color: Colors.grey,
              ),
            ],
          ),
        ],
    );
  }
}