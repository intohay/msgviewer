import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../utils/database_helper.dart';
import '../widgets/inline_image.dart';
import '../widgets/inline_video.dart';

class MediaPage extends StatefulWidget {
  final String name;
  final String iconPath;
  final String callMeName;

  const MediaPage({
    Key? key,
    required this.name,
    required this.iconPath,
    required this.callMeName,
  }) : super(key: key);

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> with SingleTickerProviderStateMixin {
  final dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> imageList = [];
  List<Map<String, dynamic>> videoList = [];
  List<Map<String, dynamic>> audioList = [];

  bool isLoading = true;

  // ★ オーディオプレイヤー関連
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentAudioPath;   // 再生中の音声ファイルパス
  String? _currentAudioTitle;  // リスト表示用のタイトル等（必要なら）
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isSeeking = false;
  double _sliderValue = 0;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _loadMedia();

    // ★ AudioPlayer のストリーム購読
    _audioPlayer.durationStream.listen((d) {
      setState(() {
        _duration = d ?? Duration.zero;
      });
    });
    _audioPlayer.positionStream.listen((p) {
      if (!_isSeeking) {
        setState(() {
          _position = p;
          _sliderValue = p.inMilliseconds.toDouble();
        });
      }
    });
    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
        // 再生完了したらリセット
        if (state.processingState == ProcessingState.completed) {
          _resetAudioPlayer();
        }
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  /// DBから画像・動画・音声をまとめて取得
  Future<void> _loadMedia() async {
    final imagesRaw = await dbHelper.getImageMessages(widget.name);
    final videosRaw = await dbHelper.getVideoMessages(widget.name);
    final audiosRaw = await dbHelper.getAudioMessages(widget.name);

    setState(() {
      imageList = imagesRaw.map((e) => Map<String, dynamic>.from(e)).toList();
      videoList = videosRaw.map((e) => Map<String, dynamic>.from(e)).toList();
      audioList = audiosRaw.map((e) => Map<String, dynamic>.from(e)).toList();
      isLoading = false;
    });
  }

  /// 音声を再生する
  Future<void> _playAudio(String path, String? title) async {
    // 既に再生中のものとは別ファイルならリセット
    if (_currentAudioPath != path) {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(path);
    }
    setState(() {
      _currentAudioPath = path;
      _currentAudioTitle = title ?? p.basename(path);
      _isPlaying = true;
    });
    _audioPlayer.play();
  }

  /// 再生位置・ステータスをリセット
  void _resetAudioPlayer() {
    _audioPlayer.seek(Duration.zero);
    _audioPlayer.pause();
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
      _sliderValue = 0;
    });
  }

  /// 再生/一時停止ボタン
  void _togglePlayback() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  /// 音量ミュート/復帰
  void _toggleVolume() {
    if (_volume > 0) {
      _setVolume(0);
    } else {
      _setVolume(1);
    }
  }

  void _setVolume(double vol) {
    _audioPlayer.setVolume(vol);
    setState(() {
      _volume = vol;
    });
  }

  /// スライダー開始
  void _onSeekStart() {
    setState(() {
      _isSeeking = true;
    });
  }

  /// スライダー変更中
  void _onSeekChange(double value) {
    setState(() {
      _sliderValue = value;
    });
  }

  /// スライダー終了
  void _onSeekEnd(double value) {
    _audioPlayer.seek(Duration(milliseconds: value.toInt()));
    setState(() {
      _isSeeking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // 画像, 動画, 音声の3タブ
      child: Scaffold(
        appBar: AppBar(
          title: Text("${widget.name} のメディア一覧"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.image)),       // 画像
              Tab(icon: Icon(Icons.video_file)),  // 動画
              Tab(icon: Icon(Icons.audiotrack)),  // 音声
            ],
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // 画像タブ
                  _buildGroupedGrid(imageList, "画像がありません", isImage: true),
                  // 動画タブ
                  _buildGroupedGrid(videoList, "動画がありません", isImage: false),
                  // 音声タブ（リスト + 下部プレイヤー）
                  _buildAudioList(audioList, "音声がありません"),
                ],
              ),
        // ★ 下部に常に表示するオーディオプレイヤー
        bottomNavigationBar: _buildAudioPlayerBar(),
      ),
    );
  }

  //==================================================
  // 画像・動画を「年月ごと」にグループ化し、
  // ListView の中に「見出し + 4列グリッド」を表示
  //==================================================
  Widget _buildGroupedGrid(List<Map<String, dynamic>> items, String emptyMessage, {required bool isImage}) {
    if (items.isEmpty) {
      return Center(child: Text(emptyMessage));
    }

    final groupedData = _groupByYearMonth(items);
    final sortedKeys = groupedData.keys.toList()..sort((a, b) => a.compareTo(b));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final ymKey = sortedKeys[index];
        final rows = groupedData[ymKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 年月見出し
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                ymKey,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // グリッド（4列）
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 0,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, idx) {
                final row = rows[idx];
                final filePath = row['filepath'] as String;
                final thumbPath = row['thumb_filepath'] as String? ?? "";

                if (isImage) {
                  // 画像
                  return InlineImage(
                    imagePath: filePath,
                    thumbnailPath: thumbPath.isNotEmpty ? thumbPath : filePath,
                    isSquare: true,
                  );
                } else {
                  // 動画
                  return InlineVideo(
                    videoPath: filePath,
                    thumbnailPath: thumbPath,
                    isSquare: true,
                    showPlayIcon: false,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  //==================================================
  // 音声リスト（タップで再生開始）
  //==================================================
  Widget _buildAudioList(List<Map<String, dynamic>> items, String emptyMessage) {
    if (items.isEmpty) {
      return Center(child: Text(emptyMessage));
    }

    final groupedData = _groupByYearMonth(items);
    final sortedKeys = groupedData.keys.toList()..sort((a, b) => a.compareTo(b));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final ymKey = sortedKeys[index];
        final rows = groupedData[ymKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 年月見出し
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                ymKey,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // リスト表示
            Column(
              children: rows.map((row) {
                final filePath = row['filepath'] as String;
                final dateString = row['date'] as String; // 例: "2025-03-17 ..."
                final dt = DateTime.parse(dateString);
                final timeLabel = _formatShortDateTime(dt);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: widget.iconPath.startsWith('assets/')
                        ? AssetImage(widget.iconPath) as ImageProvider
                        : FileImage(File(widget.iconPath)),
                  ),
                  title: Text(widget.name),
                  subtitle: Text(timeLabel),
                  trailing: Text(_calcAudioLength(row)), // 長さを表示するなら
                  onTap: () {
                    // タップで再生開始
                    _playAudio(filePath, "${widget.name} $timeLabel");
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  /// 下部のオーディオプレイヤー
  Widget _buildAudioPlayerBar() {
    // 曲を選んでいない場合は表示しない
    if (_currentAudioPath == null) {
      return const SizedBox.shrink();
    }

    
  

    final double totalMs = _duration.inMilliseconds.toDouble().clamp(0, double.infinity).toDouble();
    final double currentMs = _sliderValue.clamp(0, totalMs).toDouble();

    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ★ タイトル（再生中の音声名など）
          Text(
            _currentAudioTitle ?? p.basename(_currentAudioPath!),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          // ★ スライダー
          Slider(
            value: currentMs,
            max: totalMs > 0 ? totalMs : 1,
            onChangeStart: (_) => _onSeekStart(),
            onChanged: (value) => _onSeekChange(value),
            onChangeEnd: (value) => _onSeekEnd(value),
            activeColor: Colors.blue,
            inactiveColor: Colors.grey.shade300,
          ),
          // ★ ボタン類 + 時間表示
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(_volume > 0 ? Icons.volume_up : Icons.volume_off, color: Colors.blue),
                onPressed: _toggleVolume,
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40, color: Colors.blue),
                onPressed: _togglePlayback,
              ),
              Text(
                "${_formatDuration(_position)} / ${_formatDuration(_duration)}",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 年月ごとにグループ化
  Map<String, List<Map<String, dynamic>>> _groupByYearMonth(List<Map<String, dynamic>> items) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var row in items) {
      final dt = DateTime.parse(row['date']);
      final String key = "${dt.year}年${dt.month.toString().padLeft(2, '0')}月";
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(row);
    }
    return grouped;
  }

  /// 日付+時刻の短いフォーマット
  String _formatShortDateTime(DateTime dt) {
    
    return "${dt.year}/${dt.month}/${dt.day} ${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)} ";
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  /// 時間表記 "mm:ss"
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  /// 音声の長さなどをDBに入れてない場合は "" を返すか、
  /// あるいは計算して表示するなど
  String _calcAudioLength(Map<String, dynamic> row) {
    // ここではダミーで "" を返す
    // もし音声の長さを事前に計算してDBに保存しているなら表示
    return "";
  }
}
