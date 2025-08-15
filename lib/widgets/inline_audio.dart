import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class InlineAudio extends StatefulWidget {
  final String audioPath;

  const InlineAudio({Key? key, required this.audioPath}) : super(key: key);

  @override
  State<InlineAudio> createState() => _InlineAudioState();
}

class _InlineAudioState extends State<InlineAudio> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isSeeking = false; // ✅ スライダー操作中かどうか
  double _volume = 1.0;
  double _sliderValue = 0; // ✅ 一時的にスライダーの値を保持

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    
    // ファイルが存在するかチェック
    final audioFile = File(widget.audioPath);
    if (audioFile.existsSync()) {
      _audioPlayer.setFilePath(widget.audioPath).catchError((error) {
        print('InlineAudio: Error loading audio file: $error');
        return null;
      });
    } else {
      print('InlineAudio: Audio file not found at: ${widget.audioPath}');
    }

    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _resetAudioPlayer();
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    // ファイルが存在するかチェック
    final audioFile = File(widget.audioPath);
    if (!audioFile.existsSync()) {
      print('InlineAudio: Cannot play - file not found at: ${widget.audioPath}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音声ファイルが見つかりません')),
      );
      return;
    }
    
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play().catchError((error) {
        print('InlineAudio: Error playing audio: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('音声の再生に失敗しました')),
          );
        }
      });
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _resetAudioPlayer() async {
    await _audioPlayer.pause();
    await _audioPlayer.seek(Duration.zero);
    setState(() {
      _isPlaying = false;
    });
  }

  void _setVolume(double volume) {
    _audioPlayer.setVolume(volume);
    setState(() {
      _volume = volume;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration?>(
            stream: _audioPlayer.durationStream,
            builder: (context, snapshot) {
              final duration = snapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _audioPlayer.positionStream,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  
                  // ✅ スライダー操作中は再生位置を更新しない
                  if (!_isSeeking) {
                    _sliderValue = position.inMilliseconds.toDouble();
                  }
                  return Column(
                    children: [
                      // ✅ スライダー（進行状況バー）
                      Slider(
                        value: _sliderValue.clamp(0, duration.inMilliseconds.toDouble()), // ✅ Update slider value
                        max: duration.inMilliseconds.toDouble(),
                        onChangeStart: (_) {
                          _isSeeking = true;
                        },
                        onChanged: (value) {
                          setState(() {
                            _sliderValue = value;
                          });
                        },
                        onChangeEnd: (value) {
                          _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                          setState(() {
                            _isSeeking = false;
                          });
                        },
                        activeColor: Colors.blue,
                        inactiveColor: Colors.grey.shade300,
                      ),
                      // ✅ コントロール部分（アイコン・再生ボタン・時間）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 🔊 ボリュームアイコン
                          IconButton(
                            icon: Icon(
                              _volume > 0 ? Icons.volume_up : Icons.volume_off,
                              color: Colors.blue,
                            ),
                            onPressed: () {
                              _setVolume(_volume > 0 ? 0 : 1);
                            },
                          ),
                          // ▶️ 再生/停止ボタン
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 40,
                              color: Colors.blue,
                            ),
                            onPressed: _togglePlayback,
                          ),
                          // ⏱ 時間表示
                          Text(
                            "${_formatDuration(position)} / ${_formatDuration(duration)}",
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
