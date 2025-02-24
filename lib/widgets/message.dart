import 'package:flutter/material.dart';
import 'inline_image.dart';
import 'inline_video.dart';
import 'inline_audio.dart';

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
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(height: 8),
              Text(
                  "${senderName}　${_datetimeConverter(time)}",
                  style: TextStyle(
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
                    
                    if(mediaPath != null)
                      ifMedia(mediaPath!),
                    if(message != null && message!.isNotEmpty)
                      Text(
                        message!,
                        style: TextStyle(
                          color: Colors.black,
                        ),
                      ),
                  ],
                )
              ),
            ],
          ),
        ),
      ],
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
