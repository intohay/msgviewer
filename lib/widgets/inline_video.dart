import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/overlay_manager.dart';
import 'media_viewer_overlay.dart';

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
  
  /// 全メディアリスト（スワイプでの切り替え用）
  final List<Map<String, dynamic>>? allMedia;
  
  /// 現在のメディアのインデックス
  final int? currentIndex;
  
  /// トーク名（トーク画面へのジャンプ用）
  final String? talkName;
  
  /// 動画の長さ（ミリ秒）
  final int? videoDurationMs;
  
  /// メッセージテキスト（オーバーレイ表示用）
  final String? message;
  
  /// ユーザーの呼ばれたい名前
  final String? callMeName;

  const InlineVideo({
    super.key,
    required this.videoPath,
    required this.thumbnailPath,
    this.isSquare = false,
    this.showPlayIcon = true,
    this.time,
    this.allMedia,
    this.currentIndex,
    this.talkName,
    this.videoDurationMs,
    this.message,
    this.callMeName,
  });

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  final OverlayManager _overlayManager = OverlayManager();
  String? _thumbnailPath;
  bool _isLoading = true;
  double _aspectRatio = 16 / 9;
  Duration? _videoDuration;

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

  /// サムネイル画像のアスペクト比を取得 + 動画の長さを取得
  Future<void> _initializeDisplay() async {
    // videoDurationMsが渡されている場合はそれを使用、なければ動画から取得
    if (widget.videoDurationMs != null) {
      _videoDuration = Duration(milliseconds: widget.videoDurationMs!);
    } else {
      await _loadVideoDuration();
    }
    
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
        debugPrint('InlineVideo: Error loading thumbnail: $e');
        if (mounted) {
          setState(() {
            _thumbnailPath = null;
            _isLoading = false;
          });
        }
      }
    } else {
      // サムネイルがない場合
      debugPrint('InlineVideo: Thumbnail not found at: ${widget.thumbnailPath}');
      if (mounted) {
        setState(() {
          _thumbnailPath = null;
          _isLoading = false;
        });
      }
    }
  }

  /// 動画の長さを取得
  Future<void> _loadVideoDuration() async {
    try {
      final videoFile = File(widget.videoPath);
      if (await videoFile.exists()) {
        // 動画の長さを取得
        final controller = VideoPlayerController.file(videoFile);
        await controller.initialize();
        
        if (mounted) {
          setState(() {
            _videoDuration = controller.value.duration;
          });
        }
        
        controller.dispose();
      }
    } catch (e) {
      debugPrint('InlineVideo: Error loading video metadata: $e');
    }
  }

  /// フルスクリーンの動画再生をオーバーレイで表示
  void _showOverlay(BuildContext context) {
    // allMediaがない場合は現在の動画のみのリストを作成
    final List<Map<String, dynamic>> mediaList;
    final int initialIndex;
    
    if (widget.allMedia != null && widget.allMedia!.isNotEmpty) {
      mediaList = widget.allMedia!;
      initialIndex = widget.currentIndex ?? 0;
    } else {
      // 単体の動画を表示する場合
      mediaList = [{
        'filepath': widget.videoPath,
        'thumb_filepath': widget.thumbnailPath,
        'text': widget.message,
        'date': widget.time?.toIso8601String(),
        'video_duration': widget.videoDurationMs,
      }];
      initialIndex = 0;
    }
    
    MediaViewerOverlay.show(
      context: context,
      allMedia: mediaList,
      initialIndex: initialIndex,
      overlayManager: _overlayManager,
      talkName: widget.talkName,
      callMeName: widget.callMeName,
      onLoadMoreMedia: widget.allMedia != null ? (currentMedia) {
        // 追加のメディアを読み込むロジックをここに実装
        // 現時点では既存のリストを使用
      } : null,
    );
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
          debugPrint('InlineVideo: Error displaying thumbnail: $error');
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

    // 動画の長さと音声インジケーターのオーバーレイ
    List<Widget> overlayChildren = [
      thumbnailWidget,
    ];
    
    // 再生アイコンを表示
    if (widget.showPlayIcon) {
      overlayChildren.add(playIcon);
    }
    
    // 動画の長さと音声アイコンを表示（右下）
    if (_videoDuration != null) {
      overlayChildren.add(
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatDuration(_videoDuration!),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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
          children: overlayChildren,
        ),
      );
    } else {
      // ★ 従来の表示
      displayedWidget = LayoutBuilder(builder: (context, constraints) {
        const double fixedHeight = 250.0;
        final double calculatedWidth = fixedHeight * _aspectRatio;
        final double maxWidth = constraints.maxWidth;

        return Center(
          child: SizedBox(
            height: fixedHeight,
            width: calculatedWidth > maxWidth ? maxWidth : calculatedWidth,
            child: Stack(
              fit: StackFit.expand,
              children: overlayChildren,
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
          debugPrint('InlineVideo: Video file not found at: ${widget.videoPath}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('動画ファイルが見つかりません')),
          );
          return;
        }
        // フルスクリーン再生をオーバーレイ表示
        _showOverlay(context);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: displayedWidget,
      ),
    );
  }
}
