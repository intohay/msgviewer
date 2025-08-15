import 'package:flutter/material.dart';
import 'inline_image.dart';
import 'inline_video.dart';
import 'inline_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

class Message extends StatelessWidget {
  final String? message;
  final String senderName;
  final DateTime time;
  final String avatarAssetPath;
  final String? mediaPath;
  final String? thumbPath;
  final bool isFavorite; // ★ ここでお気に入りフラグを受け取る
  
  final String? highlightQuery;
  
  // スワイプで切り替えるためのメディアリスト
  final List<Map<String, dynamic>>? allMedia;
  final int? currentMediaIndex;

  const Message({
    Key? key,
    this.message,
    required this.senderName,
    required this.time,
    required this.avatarAssetPath,
    this.mediaPath,
    this.thumbPath,
    this.isFavorite = false,

    this.highlightQuery,
    this.allMedia,
    this.currentMediaIndex,
  }) : super(key: key);

  /// メディアの種類を判定して対応ウィジェットを返す
  Widget ifMedia(String mediaPath, String thumbPath) {
    if (mediaPath.endsWith('.jpg') || mediaPath.endsWith('.png')) {
      return InlineImage(
        imagePath: mediaPath, 
        thumbnailPath: thumbPath,
        message: message,
        time: time,
        allMedia: allMedia,
        currentIndex: currentMediaIndex,
      );
    } else if (mediaPath.endsWith('.m4a') ||
        (mediaPath.endsWith('.mp4') && mediaPath.contains('_3_'))) {
      return InlineAudio(audioPath: mediaPath);
    } else if (mediaPath.endsWith('.mp4')) {
      return InlineVideo(
        videoPath: mediaPath, 
        thumbnailPath: thumbPath,
        time: time,
        allMedia: allMedia,
        currentIndex: currentMediaIndex,
      );
    } else {
      return const Text("Unsupported media type");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // アバター
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: CircleAvatar(
            backgroundImage: AssetImage(avatarAssetPath),
            radius: 20,
          ),
        ),
        const SizedBox(width: 10),
        // メッセージ本文
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              
              // ★ 「名前＋時刻＋星」を同じ行に配置
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "$senderName　${_datetimeConverter(time)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 11,
                    ),
                  ),
                  // お気に入りなら星アイコンを表示
                  if (isFavorite)
                    const Padding(
                      padding: EdgeInsets.only(right: 22.0),
                        child: Icon(
                          Icons.star,
                          color: Colors.orangeAccent,
                          size: 16,
                      ),
                    ), 
                ],
              ),

              // メッセージボックス
              Container(
                margin: const EdgeInsets.only(top: 5.0, right: 15.0),
                padding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 15.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(3.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (mediaPath != null &&
                        mediaPath!.isNotEmpty)
                      ifMedia(mediaPath!, thumbPath ?? ''),
                    if (message != null && message!.isNotEmpty)
                      _buildMessageText(message!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// URLを検出してリンク化する
  Widget _buildMessageText(String text) {
    final RegExp linkRegex = RegExp(
      r'((https?:\/\/)?([\w-]+(\.[\w-]+)+(:\d+)?(\/\S*)?))',
      caseSensitive: false,
    );

    final List<InlineSpan> spans = [];
    final matches = linkRegex.allMatches(text);
    int lastMatchEnd = 0;

    for (final match in matches) {
      // 通常テキスト部分
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      // URL部分
      final String url = text.substring(match.start, match.end);
      final String formattedUrl = url.startsWith('http') ? url : 'https://$url';

      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final Uri uri = Uri.parse(formattedUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );

      lastMatchEnd = match.end;
    }

    // 残りの通常テキスト
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black),
        children: spans,
      ),
    );
  }

  String _datetimeConverter(DateTime datetime) {
    return "${datetime.year.toString().padLeft(4, '0')}/"
        "${datetime.month.toString().padLeft(2, '0')}/"
        "${datetime.day.toString().padLeft(2, '0')} "
        "${datetime.hour.toString().padLeft(2, '0')}:"
        "${datetime.minute.toString().padLeft(2, '0')}";
  }
}
