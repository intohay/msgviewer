import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

import '../utils/database_helper.dart';
import '../utils/helper.dart';
import '../widgets/inline_image.dart';
import '../widgets/inline_video.dart';

class MediaPage extends StatefulWidget {
  final String name;
  final String iconPath;
  final String callMeName;

  const MediaPage({
    super.key,
    required this.name,
    required this.iconPath,
    required this.callMeName,
  });

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> with SingleTickerProviderStateMixin {
  final dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> imageList = [];
  List<Map<String, dynamic>> videoList = [];
  List<Map<String, dynamic>> audioList = [];

  bool isLoading = true;
  bool _hasCalculatedVideoDurations = false;
  bool _hasCalculatedAudioDurations = false;
  
  // ★ TabController
  late TabController _tabController;
  int _currentTabIndex = 0;
  
  // ★ ScrollController for each tab
  final ScrollController _imageScrollController = ScrollController();
  final ScrollController _videoScrollController = ScrollController();
  final ScrollController _audioScrollController = ScrollController();
  
  // ★ 年月セクションへのスクロール用キー（各タブ）
  final Map<String, GlobalKey> _imageSectionKeys = {};
  final Map<String, GlobalKey> _videoSectionKeys = {};

  // ★ オーディオプレイヤー関連
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentAudioPath;   // 再生中の音声ファイルパス
  String? _currentAudioTitle;  // リスト表示用のタイトル等（必要なら）
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isSeeking = false;
  double _sliderValue = 0;
  
  // StreamSubscriptions
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _loadMedia();
    
    // ★ TabController の初期化
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() async {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
      
      // 動画タブ(index:1)に初めて訪れた時、動画の長さを計算
      if (_tabController.index == 1 && !_hasCalculatedVideoDurations) {
        _hasCalculatedVideoDurations = true;
        await _calculateVideoDurations();
      }
      
      // 音声タブ(index:2)に初めて訪れた時、音声の長さを計算
      if (_tabController.index == 2 && !_hasCalculatedAudioDurations) {
        _hasCalculatedAudioDurations = true;
        await _calculateAudioDurations();
      }
      
      // 音声タブ(index:2)以外に移動したら、音声プレイヤーをリセット
      if (_tabController.index != 2) {
        _resetAudioPlayer();
      }
    });

    // ★ AudioPlayer のストリーム購読
    _durationSubscription = _audioPlayer.durationStream.listen((d) {
      if (mounted) {
        setState(() {
          _duration = d ?? Duration.zero;
        });
      }
    });
    _positionSubscription = _audioPlayer.positionStream.listen((p) {
      if (!_isSeeking && mounted) {
        setState(() {
          _position = p;
          _sliderValue = p.inMilliseconds.toDouble();
        });
      }
    });
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          // 再生完了したらリセット
          if (state.processingState == ProcessingState.completed) {
            _resetAudioPlayer();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _tabController.dispose();
    _audioPlayer.dispose();
    _imageScrollController.dispose();
    _videoScrollController.dispose();
    _audioScrollController.dispose();
    super.dispose();
  }

  //==================================================
  // セクションキー取得/生成
  //==================================================
  GlobalKey _getSectionKey(String ymKey, {required bool isImage}) {
    final map = isImage ? _imageSectionKeys : _videoSectionKeys;
    return map.putIfAbsent(ymKey, () => GlobalKey());
  }

  void _scrollToYearMonth(DateTime dt, {required bool isImage}) {
    final ymKey = "${dt.year}年${dt.month.toString().padLeft(2, '0')}月";
    final key = (isImage ? _imageSectionKeys : _videoSectionKeys)[ymKey];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
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
  
  /// 既存の動画の長さを計算してデータベースに保存
  Future<void> _calculateVideoDurations() async {
    for (var video in videoList) {
      if (video['video_duration'] == null) {
        final filePath = video['filepath'] as String?;
        if (filePath != null && File(filePath).existsSync()) {
          try {
            final controller = VideoPlayerController.file(File(filePath));
            await controller.initialize();
            final duration = controller.value.duration;
            video['video_duration'] = duration.inMilliseconds;
            
            // データベースを更新
            await dbHelper.updateVideoDuration(video['id'], duration.inMilliseconds);
            controller.dispose();
          } catch (e) {
            debugPrint('Error calculating video duration: $e');
          }
        }
      }
    }
    setState(() {});
  }
  
  /// 既存の音声の長さを計算してデータベースに保存
  Future<void> _calculateAudioDurations() async {
    for (var audio in audioList) {
      if (audio['audio_duration'] == null) {
        final filePath = audio['filepath'] as String?;
        if (filePath != null && File(filePath).existsSync()) {
          try {
            final player = AudioPlayer();
            final duration = await player.setFilePath(filePath);
            if (duration != null) {
              audio['audio_duration'] = duration.inMilliseconds;
              
              // データベースを更新
              await dbHelper.updateAudioDuration(audio['id'], duration.inMilliseconds);
            }
            player.dispose();
          } catch (e) {
            debugPrint('Error calculating audio duration: $e');
          }
        }
      }
    }
    setState(() {});
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
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.name} のメディア一覧"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.image)),       // 画像
            Tab(icon: Icon(Icons.video_file)),  // 動画
            Tab(icon: Icon(Icons.audiotrack)),  // 音声
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 画像タブ
                _buildGroupedGrid(imageList, "画像がありません", isImage: true),
                // 動画タブ
                _buildGroupedGrid(videoList, "動画がありません", isImage: false),
                // 音声タブ（リスト + 下部プレイヤー）
                _buildAudioList(audioList, "音声がありません"),
              ],
            ),
      // ★ フローティングアクションボタン（最上部・最下部ジャンプ）
      floatingActionButton: _buildFloatingButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // ★ 音声タブの時のみ表示するオーディオプレイヤー
      bottomNavigationBar: _currentTabIndex == 2 ? _buildAudioPlayerBar() : null,
    );
  }
  
  // ★ 最上部・最下部へのジャンプボタンを構築
  Widget _buildFloatingButtons() {
    // 各タブに応じたScrollControllerを取得
    ScrollController? currentController;
    if (_currentTabIndex == 0) {
      currentController = _imageScrollController;
    } else if (_currentTabIndex == 1) {
      currentController = _videoScrollController;
    } else if (_currentTabIndex == 2) {
      currentController = _audioScrollController;
    }
    
    // データが空の場合はボタンを表示しない
    if ((_currentTabIndex == 0 && imageList.isEmpty) ||
        (_currentTabIndex == 1 && videoList.isEmpty) ||
        (_currentTabIndex == 2 && audioList.isEmpty)) {
      return const SizedBox.shrink();
    }
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 最上部へジャンプボタン
        FloatingActionButton.small(
          heroTag: "toTop",
          onPressed: () {
            currentController?.animateTo(
              0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          },
          child: const Icon(Icons.arrow_upward),
        ),
        const SizedBox(height: 8),
        // 最下部へジャンプボタン
        FloatingActionButton.small(
          heroTag: "toBottom",
          onPressed: () {
            currentController?.animateTo(
              currentController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          },
          child: const Icon(Icons.arrow_downward),
        ),
      ],
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
      controller: isImage ? _imageScrollController : _videoScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final ymKey = sortedKeys[index];
        final rows = groupedData[ymKey]!;

        return Column(
          key: _getSectionKey(ymKey, isImage: isImage),
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
                final message = row['text'] as String?;
                final dateStr = row['date'] as String?;
                DateTime? dateTime;
                if (dateStr != null) {
                  dateTime = DateTime.tryParse(dateStr);
                }

                // Apply replacePlaceHolders to the message text
                final processedMessage = message != null 
                    ? replacePlaceHolders(message, widget.callMeName)
                    : null;

                if (isImage) {
                  // 画像
                  return InlineImage(
                    imagePath: filePath,
                    thumbnailPath: thumbPath.isNotEmpty ? thumbPath : filePath,
                    isSquare: true,
                    message: processedMessage,
                    time: dateTime,
                    // 画像タブでは画像のみのリストを渡す（メディア一覧は古い順なので逆順にしない）
                    allMedia: imageList,
                    currentIndex: imageList.indexWhere((item) => item['id'] == row['id']),
                    // メディア一覧から開く場合はtalkNameを渡さない（閉じる時にpopしないため）
                    callMeName: widget.callMeName,
                    onViewingChanged: (dt) {
                      if (dt != null) {
                        _scrollToYearMonth(dt, isImage: true);
                      }
                    },
                    onViewerClosed: (dt) {
                      if (dt != null) {
                        _scrollToYearMonth(dt, isImage: true);
                      }
                    },
                  );
                } else {
                  // 動画
                  final durationMs = row['video_duration'] as int?;
                  
                  return InlineVideo(
                    videoPath: filePath,
                    thumbnailPath: thumbPath.isNotEmpty ? thumbPath : filePath,
                    isSquare: true,
                    message: processedMessage,
                    time: dateTime,
                    // 動画タブでは動画のみのリストを渡す（メディア一覧は古い順なので逆順にしない）
                    allMedia: videoList,
                    currentIndex: videoList.indexWhere((item) => item['id'] == row['id']),
                    // メディア一覧から開く場合はtalkNameを渡さない（閉じる時にpopしないため）
                    videoDurationMs: durationMs,
                    callMeName: widget.callMeName,
                    onViewingChanged: (dt) {
                      if (dt != null) {
                        _scrollToYearMonth(dt, isImage: false);
                      }
                    },
                    onViewerClosed: (dt) {
                      if (dt != null) {
                        _scrollToYearMonth(dt, isImage: false);
                      }
                    },
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
      controller: _audioScrollController,
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 音声の長さを非同期で取得して表示
                      FutureBuilder<String>(
                        future: _getAudioDuration(filePath),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.timer, size: 14, color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    snapshot.data!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox(width: 60); // プレースホルダー
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20),
                        onPressed: () {
                          // トーク画面の該当位置にジャンプ
                          Navigator.of(context).pop({
                            'jumpToDate': dt,
                          });
                        },
                      ),
                    ],
                  ),
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
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8.0,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 16.0,
              ),
              trackHeight: 4.0,
            ),
            child: Slider(
              value: currentMs,
              max: totalMs > 0 ? totalMs : 1,
              onChangeStart: (_) => _onSeekStart(),
              onChanged: (value) => _onSeekChange(value),
              onChangeEnd: (value) => _onSeekEnd(value),
              activeColor: Colors.blue,
              inactiveColor: Colors.grey.shade300,
            ),
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
  /// 音声ファイルの長さを取得（キャッシュ付き）
  final Map<String, String> _audioDurationCache = {};
  
  Future<String> _getAudioDuration(String filePath) async {
    // キャッシュに存在する場合はそれを返す
    if (_audioDurationCache.containsKey(filePath)) {
      return _audioDurationCache[filePath]!;
    }
    
    try {
      final player = AudioPlayer();
      final duration = await player.setFilePath(filePath);
      await player.dispose();
      
      if (duration != null) {
        final formatted = _formatDuration(duration);
        _audioDurationCache[filePath] = formatted;
        return formatted;
      }
    } catch (e) {
      debugPrint('Error getting audio duration: $e');
    }
    
    return "";
  }
  
}
