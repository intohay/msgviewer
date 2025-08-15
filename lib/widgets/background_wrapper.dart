import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundWrapper extends StatefulWidget {
  final Widget child;
  final String talkName;
  
  const BackgroundWrapper({super.key, required this.child, required this.talkName});

  @override
  State<BackgroundWrapper> createState() => _BackgroundWrapperState();
}

class _BackgroundWrapperState extends State<BackgroundWrapper> {
  String? _backgroundImagePath;
  double _opacity = 0.23;
  BoxFit _imageFit = BoxFit.cover;
  
  @override
  void initState() {
    super.initState();
    _loadBackgroundSettings();
  }

  @override
  void didUpdateWidget(BackgroundWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // TalkPageでsetStateが呼ばれたときに設定を再読み込み
    _loadBackgroundSettings();
  }

  Future<void> _loadBackgroundSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundImagePath = prefs.getString('${widget.talkName}_background_image_path');
      _opacity = prefs.getDouble('${widget.talkName}_background_opacity') ?? 0.23;
      final fitIndex = prefs.getInt('${widget.talkName}_background_fit') ?? 0;
      _imageFit = BoxFit.values[fitIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_backgroundImagePath == null || !File(_backgroundImagePath!).existsSync()) {
      return widget.child;
    }

    return Stack(
      children: [
        // Background image
        Positioned.fill(
          child: Opacity(
            opacity: 1.0 - (_opacity / 100),
            child: _imageFit == BoxFit.none
                ? Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: FileImage(File(_backgroundImagePath!)),
                        repeat: ImageRepeat.repeat,
                      ),
                    ),
                  )
                : Image.file(
                    File(_backgroundImagePath!),
                    fit: _imageFit,
                  ),
          ),
        ),
        // Main content
        widget.child,
      ],
    );
  }
}