import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import '../utils/overlay_manager.dart';
import '../utils/helper.dart';

class MediaViewerOverlay {
  static void show({
    required BuildContext context,
    required List<Map<String, dynamic>> allMedia,
    required int initialIndex,
    required OverlayManager overlayManager,
    String? talkName,  // トーク画面へのジャンプ用
    String? callMeName,  // ユーザーの呼ばれたい名前
    Future<int> Function(List<Map<String, dynamic>> displayedMedia, int currentIndex, bool towardsEnd)? onLoadMoreMedia,  // 追加メディア読み込み（戻り値: 先頭に追加した件数）
    void Function(DateTime? jumpToDate, int lastViewedIndex, List<Map<String, dynamic>> displayedMedia)? onClose, // クローズ時通知
    void Function(DateTime? viewingDate)? onViewedMediaChanged, // ページ変更時通知
  }) {
    // スワイプ用の変数
    double verticalDragOffset = 0;
    double opacity = 1.0;
    bool showInfo = true;
    Timer? hideTimer;
    
    // PageView用のコントローラー
    final PageController pageController = PageController(
      initialPage: initialIndex,
    );
    int currentPageIndex = initialIndex;
    
    // フルスクリーンで表示するメディアリスト（動的に更新される）
    List<Map<String, dynamic>> displayedMedia = List.from(allMedia);
    
    // 最後にフルスクリーンで表示していたインデックスを記録
    int lastViewedIndex = initialIndex;
    
    // 動画コントローラーのマップ（インデックスごとに管理）
    Map<int, VideoPlayerController> videoControllers = {};
    // シーク中フラグと一時的なドラッグ位置
    bool isDraggingSeek = false;
    double dragPercent = 0.0; // 0.0 - 1.0
    
    // PageViewのスクロール物理を管理するための変数
    ScrollPhysics pageViewPhysics = const AlwaysScrollableScrollPhysics();
    
    // 10秒後に自動的に情報を非表示にする
    void startHideTimer(Function setState) {
      hideTimer?.cancel();
      hideTimer = Timer(const Duration(seconds: 10), () {
        setState(() {
          showInfo = false;
        });
      });
    }
    
    String formatDuration(Duration duration) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final hours = twoDigits(duration.inHours);
      final minutes = twoDigits(duration.inMinutes.remainder(60));
      final seconds = twoDigits(duration.inSeconds.remainder(60));
      return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
    }
    
    final overlayEntry = OverlayEntry(
      builder: (overlayContext) => StatefulBuilder(
        builder: (context, setState) {
          // タイマーで非表示になったら状態を更新
          if (hideTimer != null && !hideTimer!.isActive) {
            showInfo = false;
          }
          
          // 初回のタイマー開始
          if (hideTimer == null && showInfo) {
            startHideTimer(setState);
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
                // 動画コントローラーを破棄
                videoControllers.forEach((_, controller) {
                  controller.dispose();
                });
                pageController.dispose();
                overlayManager.closeOverlay();
                
                // 最後に表示していたメディアの位置を返す
                final media = (lastViewedIndex >= 0 && lastViewedIndex < displayedMedia.length)
                    ? displayedMedia[lastViewedIndex]
                    : null;
                final dateStr = media != null ? media['date'] as String? : null;
                final dateTime = dateStr != null ? DateTime.tryParse(dateStr) : null;
                if (onClose != null) {
                  onClose(dateTime, lastViewedIndex, displayedMedia);
                } else if (talkName != null) {
                  // 互換: onClose が無い場合は従来通り pop で返す
                  Navigator.of(context).pop({
                    'lastViewedIndex': lastViewedIndex,
                    'updatedMedia': displayedMedia,
                    'jumpToDate': dateTime,
                  });
                }
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
                  startHideTimer(setState);
                });
              }
            },
            child: Stack(
              children: [
                // 背景（透明度変化）
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  color: Colors.black.withValues(alpha: opacity),
                ),
                // メディアとオーバーレイ（一緒に動く）
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  transform: Matrix4.translationValues(0, verticalDragOffset, 0),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: PageView.builder(
                          controller: pageController,
                          physics: pageViewPhysics,  // 動的に変更可能なphysicsを使用
                          itemCount: displayedMedia.length,
                          onPageChanged: (index) async {
                            setState(() {
                              currentPageIndex = index;
                              lastViewedIndex = index;
                              
                              // 動画の再生を制御
                              videoControllers.forEach((idx, controller) {
                                if (idx == index && controller.value.isInitialized) {
                                  controller.play();
                                } else {
                                  controller.pause();
                                }
                              });
                              
                              // 最後のページに近づいたら追加のメディアを読み込む
                              if (onLoadMoreMedia != null) {
                                // 非同期を待たずに投げる（スクロールをカクつかせないため）
                                if (index >= displayedMedia.length - 3) {
                                  onLoadMoreMedia(displayedMedia, index, true).then((_) {
                                    setState(() {});
                                  });
                                } else if (index <= 2) {
                                  onLoadMoreMedia(displayedMedia, index, false).then((addedToFront) {
                                    if (addedToFront > 0 && pageController.hasClients) {
                                      final newIndex = index + addedToFront;
                                      pageController.jumpToPage(newIndex);
                                      currentPageIndex = newIndex;
                                      lastViewedIndex = newIndex;
                                    }
                                    setState(() {});
                                  });
                                }
                              }
                            });
                            // 閲覧中のメディア日時を通知
                            if (onViewedMediaChanged != null) {
                              if (index < displayedMedia.length) {
                                final current = displayedMedia[index];
                                final dateStr = current['date'] as String?;
                                final dt = dateStr != null ? DateTime.tryParse(dateStr) : null;
                                onViewedMediaChanged(dt);
                              }
                            }
                          },
                          itemBuilder: (context, index) {
                            final media = displayedMedia[index];
                            final mediaPath = media['filepath'] as String;
                            
                            // 画像か動画かを判定
                            if (mediaPath.endsWith('.jpg') || mediaPath.endsWith('.png')) {
                              // 画像表示
                              return InteractiveViewer(
                                minScale: 1.0,
                                maxScale: 3.0,
                                boundaryMargin: EdgeInsets.zero,
                                constrained: true,
                                child: Center(
                                  child: Image.file(
                                    File(mediaPath),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[300],
                                        child: const Center(
                                          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            } else if (mediaPath.endsWith('.mp4')) {
                              // 動画表示
                              // コントローラーがまだ初期化されていない場合は初期化
                              if (!videoControllers.containsKey(index)) {
                                final controller = VideoPlayerController.file(File(mediaPath));
                                videoControllers[index] = controller;
                                controller.initialize().then((_) {
                                  // 初期化後、現在のページの動画なら再生開始
                                  if (currentPageIndex == index) {
                                    controller.play();
                                    controller.setLooping(true);
                                  }
                                  // 位置の更新をリスニング（初期化後に追加）
                                  controller.addListener(() {
                                    if (controller.value.isInitialized && currentPageIndex == index) {
                                      setState(() {}); // UIを更新
                                    }
                                  });
                                  // 初期化完了後にUIを更新
                                  setState(() {});
                                });
                              }
                              
                              final controller = videoControllers[index]!;
                              
                              return Stack(
                                children: [
                                  // 動画プレイヤー本体
                                  Center(
                                    child: controller.value.isInitialized
                                      ? AspectRatio(
                                          aspectRatio: controller.value.aspectRatio,
                                          child: VideoPlayer(controller),
                                        )
                                      : const CircularProgressIndicator(color: Colors.white),
                                  ),
                                  
                                  // 中央の再生コントロール
                                  if (showInfo && controller.value.isInitialized)
                                    Positioned.fill(
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            // 5秒巻き戻し
                                            GestureDetector(
                                              onTap: () {
                                                final newPosition = controller.value.position - const Duration(seconds: 5);
                                                controller.seekTo(newPosition);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade900.withValues(alpha: 0.3),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.replay_5,
                                                  size: 30,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 30),
                                            // 再生/一時停止
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (controller.value.isPlaying) {
                                                    controller.pause();
                                                  } else {
                                                    controller.play();
                                                  }
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade900.withValues(alpha: 0.3),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                                  size: 40,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 30),
                                            // 5秒早送り
                                            GestureDetector(
                                              onTap: () {
                                                final newPosition = controller.value.position + const Duration(seconds: 5);
                                                controller.seekTo(newPosition);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade900.withValues(alpha: 0.3),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.forward_5,
                                                  size: 30,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  
                                  // 下部のシークバーと時間表示（白い丸いつまみ付き）
                                  if (showInfo && controller.value.isInitialized)
                                    Positioned(
                                      bottom: 20,  // さらに下げて20に変更
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 120,  // シークバーエリア全体の高さ
                                        color: Colors.transparent,
                                        child: Stack(
                                          children: [
                                            // 透明な背景でタッチイベントをキャッチ
                                            GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onHorizontalDragStart: (_) {},
                                              onHorizontalDragUpdate: (_) {},
                                              onHorizontalDragEnd: (_) {},
                                              onVerticalDragStart: (_) {},
                                              onVerticalDragUpdate: (_) {},
                                              onVerticalDragEnd: (_) {},
                                            ),
                                            // シークバーUI
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                              child: Column(
                                                children: [
                                                  Container(
                                                    height: 60,  // タッチ領域を拡大（40 → 60）
                                                    alignment: Alignment.center,
                                                    child: LayoutBuilder(
                                                      builder: (context, constraints) {
                                                        final totalMs = controller.value.duration.inMilliseconds;
                                                        final currentMs = controller.value.position.inMilliseconds;
                                                        final baseProgress = totalMs > 0
                                                            ? (currentMs / totalMs).clamp(0.0, 1.0)
                                                            : 0.0;
                                                        final progress = isDraggingSeek ? dragPercent : baseProgress;

                                                        void seekToPercent(double percent) {
                                                          percent = percent.clamp(0.0, 1.0);
                                                          final targetMs = (totalMs * percent).toInt();
                                                          controller.seekTo(Duration(milliseconds: targetMs));
                                                        }

                                                        return GestureDetector(
                                                    behavior: HitTestBehavior.opaque,  // タッチ領域全体を反応させる
                                                    onTapDown: (details) {
                                                      final localX = details.localPosition.dx;
                                                      dragPercent = (localX / constraints.maxWidth).clamp(0.0, 1.0);
                                                      isDraggingSeek = true;
                                                      setState(() {});
                                                      seekToPercent(dragPercent);
                                                      isDraggingSeek = false;
                                                    },
                                                    onHorizontalDragStart: (details) {
                                                      isDraggingSeek = true;
                                                      dragPercent = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                                                      setState(() {});
                                                    },
                                                    onHorizontalDragUpdate: (details) {
                                                      dragPercent = ((details.localPosition.dx) / constraints.maxWidth)
                                                          .clamp(0.0, 1.0);
                                                      setState(() {});
                                                    },
                                                    onHorizontalDragEnd: (_) {
                                                      seekToPercent(dragPercent);
                                                      isDraggingSeek = false;
                                                      setState(() {});
                                                    },
                                                  child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      // 背景トラック
                                                      Container(
                                                        height: 4,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withValues(alpha: 0.3),
                                                          borderRadius: BorderRadius.circular(2),
                                                        ),
                                                      ),
                                                      // 再生済みトラック
                                                      Align(
                                                        alignment: Alignment.centerLeft,
                                                        child: Container(
                                                          height: 4,
                                                          width: constraints.maxWidth * progress,
                                                          decoration: BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius: BorderRadius.circular(2),
                                                          ),
                                                        ),
                                                      ),
                                                      // 白い丸いつまみ
                                                      Positioned(
                                                        left: (constraints.maxWidth * progress - 10)
                                                            .clamp(0.0, constraints.maxWidth - 20),
                                                        child: Container(
                                                          width: 20,
                                                          height: 20,
                                                          decoration: BoxDecoration(
                                                            color: Colors.white,
                                                            shape: BoxShape.circle,
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors.black.withValues(alpha: 0.5),
                                                                blurRadius: 4,
                                                                offset: const Offset(0, 2),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  // 時間表示
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        formatDuration(controller.value.position),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          decoration: TextDecoration.none,
                                                        ),
                                                      ),
                                                      Text(
                                                        formatDuration(controller.value.duration),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          decoration: TextDecoration.none,
                                                        ),
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
                              );
                            } else {
                              return Container();
                            }
                          },
                        ),
                      ),
                      // 上部の日時表示とナビゲーション
                      if (showInfo)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.grey.shade900.withValues(alpha: 0.3),
                            padding: EdgeInsets.only(
                              top: MediaQuery.of(context).padding.top + 15,
                              bottom: 15,
                              left: 20,
                              right: 20,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // 左側にトークへジャンプボタン（talkNameが指定されている場合のみ）
                                if (talkName != null)
                                  GestureDetector(
                                    onTap: () {
                                      // 現在表示中のメディアの日付を取得
                                      if (currentPageIndex < displayedMedia.length) {
                                        final currentMedia = displayedMedia[currentPageIndex];
                                        final dateStr = currentMedia['date'] as String?;
                                        if (dateStr != null) {
                                          final dateTime = DateTime.tryParse(dateStr);
                                          if (dateTime != null) {
                                            hideTimer?.cancel();
                                            // 動画コントローラーを破棄
                                            videoControllers.forEach((_, controller) {
                                              controller.dispose();
                                            });
                                            pageController.dispose();
                                            overlayManager.closeOverlay();
                                            
                                            // トーク画面にジャンプ（結果を通知）
                                            if (onClose != null) {
                                              onClose(dateTime, lastViewedIndex, displayedMedia);
                                            } else {
                                              // 互換: onClose が無い場合は従来通り pop で返す
                                              Navigator.of(context).pop({
                                                'jumpToDate': dateTime,
                                                'lastViewedIndex': lastViewedIndex,
                                                'updatedMedia': displayedMedia,
                                              });
                                            }
                                          }
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.open_in_new,
                                        size: 24,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(width: 40),  // スペース確保
                                
                                // 中央に日時表示とページインジケーター
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (displayedMedia.length > 1)
                                        Text(
                                          '${currentPageIndex + 1} / ${displayedMedia.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      // 現在表示中のメディアの日付を表示
                                      Builder(
                                        builder: (context) {
                                          if (currentPageIndex < displayedMedia.length) {
                                            final currentMedia = displayedMedia[currentPageIndex];
                                            final dateStr = currentMedia['date'] as String?;
                                            if (dateStr != null) {
                                              final dateTime = DateTime.tryParse(dateStr);
                                              if (dateTime != null) {
                                                return Text(
                                                  DateFormat('yyyy/MM/dd HH:mm').format(dateTime),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                    decoration: TextDecoration.none,
                                                    letterSpacing: 0.5,
                                                  ),
                                                );
                                              }
                                            }
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                // 右側の×ボタン
                                GestureDetector(
                                  onTap: () {
                                    hideTimer?.cancel();
                                    // 動画コントローラーを破棄
                                    videoControllers.forEach((_, controller) {
                                      controller.dispose();
                                    });
                                    pageController.dispose();
                                    overlayManager.closeOverlay();
                                    
                                    // 最後に表示していたメディアの位置を返す
                                    final media = (lastViewedIndex >= 0 && lastViewedIndex < displayedMedia.length)
                                        ? displayedMedia[lastViewedIndex]
                                        : null;
                                    final dateStr = media != null ? media['date'] as String? : null;
                                    final dateTime = dateStr != null ? DateTime.tryParse(dateStr) : null;
                                    if (onClose != null) {
                                      onClose(dateTime, lastViewedIndex, displayedMedia);
                                    } else if (talkName != null) {
                                      // 互換: onClose が無い場合は従来通り pop で返す
                                      Navigator.of(context).pop({
                                        'lastViewedIndex': lastViewedIndex,
                                        'updatedMedia': displayedMedia,
                                        'jumpToDate': dateTime,
                                      });
                                    }
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
                      // 下部のメッセージ表示
                      if (showInfo)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Builder(
                            builder: (context) {
                              // 現在表示中のメディアのメッセージを取得
                              if (currentPageIndex < displayedMedia.length) {
                                final currentMedia = displayedMedia[currentPageIndex];
                                final rawMessage = currentMedia['text'] as String?;
                                final currentMessage = rawMessage != null && callMeName != null
                                    ? replacePlaceHolders(rawMessage, callMeName)
                                    : rawMessage;
                                
                                if (currentMessage != null && currentMessage.isNotEmpty) {
                                  return Container(
                                    width: double.infinity,
                                    constraints: BoxConstraints(
                                      maxHeight: MediaQuery.of(context).size.height * 0.3,
                                    ),
                                    color: Colors.grey.shade900.withValues(alpha: 0.3),
                                    child: SingleChildScrollView(
                                      child: Container(
                                        padding: EdgeInsets.only(
                                          bottom: MediaQuery.of(context).padding.bottom + 20,
                                          top: 20,
                                          left: 20,
                                          right: 20,
                                        ),
                                        child: Text(
                                          currentMessage,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                            decoration: TextDecoration.none,
                                            height: 1.5,
                                          ),
                                          textAlign: TextAlign.left,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                              return const SizedBox.shrink();
                            },
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
    overlayManager.showOverlay(context, overlayEntry);
  }
}