import 'package:flutter/material.dart';
import 'inline_image.dart';
import 'inline_video.dart';
import 'inline_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

class Message extends StatelessWidget {
  final String? message;
  final String senderName;
  final String time;
  final String avatarAssetPath;
  final String? mediaPath;

  const Message({
    Key? key,
    this.message,
    required this.senderName,
    required this.time,
    required this.avatarAssetPath,
    this.mediaPath,
  }) : super(key: key);

  Widget ifMedia(String mediaPath) {
    if (mediaPath.endsWith('.jpg') || mediaPath.endsWith('.png')) {
      return InlineImage(imagePath: mediaPath);
    } else if (mediaPath.endsWith('.mp4')) {
      return InlineVideo(videoPath: mediaPath);
    } else if (mediaPath.endsWith('.m4a')) {
      return InlineAudio(audioPath: mediaPath);
    } else {
      return const Text("Unsupported media type");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: CircleAvatar(
            backgroundImage: AssetImage(avatarAssetPath),
            radius: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                "${senderName}　${_datetimeConverter(time)}",
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 11,
                ),
              ),
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
                    if (mediaPath != null) ifMedia(mediaPath!),
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

  /// **URLを検出し、通常のテキストと分割**
  Widget _buildMessageText(String text) {
    final RegExp linkRegex = RegExp(
      r'((https?:\/\/)?([\w-]+(\.[\w-]+)+(:\d+)?(\/\S*)?))',
      caseSensitive: false,
    );

    final List<InlineSpan> spans = [];
    final matches = linkRegex.allMatches(text);
    int lastMatchEnd = 0;

    for (final match in matches) {
      // 通常のテキスト部分を追加
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      // URL部分をリンク化
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

    // 残りの通常テキスト部分を追加
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

  String _datetimeConverter(String datetime) {
    if (datetime.length >= 14) {
      return datetime.substring(0, 4) + "/" +
          datetime.substring(5, 7) + "/" +
          datetime.substring(7, 9) + " " +
          datetime.substring(10, 12) + ":" +
          datetime.substring(12, 14);
    } else {
      throw FormatException("Invalid datetime format");
    }
  }
}
