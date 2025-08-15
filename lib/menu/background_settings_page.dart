import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundSettingsPage extends StatefulWidget {
  final String talkName;
  
  const BackgroundSettingsPage({super.key, required this.talkName});

  @override
  State<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends State<BackgroundSettingsPage> {
  final ImagePicker _picker = ImagePicker();
  String? _backgroundImagePath;
  double _opacity = 0.23;
  BoxFit _imageFit = BoxFit.cover;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundImagePath = prefs.getString('${widget.talkName}_background_image_path');
      _opacity = prefs.getDouble('${widget.talkName}_background_opacity') ?? 0.23;
      final fitIndex = prefs.getInt('${widget.talkName}_background_fit') ?? 0;
      _imageFit = BoxFit.values[fitIndex];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_backgroundImagePath != null) {
      await prefs.setString('${widget.talkName}_background_image_path', _backgroundImagePath!);
    } else {
      await prefs.remove('${widget.talkName}_background_image_path');
    }
    await prefs.setDouble('${widget.talkName}_background_opacity', _opacity);
    await prefs.setInt('${widget.talkName}_background_fit', BoxFit.values.indexOf(_imageFit));
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _backgroundImagePath = image.path;
      });
      await _saveSettings();
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _backgroundImagePath = null;
      _opacity = 0.23;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${widget.talkName}_background_image_path');
    await prefs.setDouble('${widget.talkName}_background_opacity', 0.23);
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('写真を選択'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('デフォルトに戻す'),
                onTap: () {
                  Navigator.pop(context);
                  _resetToDefault();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('背景設定'),
      ),
      body: Stack(
        children: [
          // Background preview - same as in TalkPage
          if (_backgroundImagePath != null && File(_backgroundImagePath!).existsSync())
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
          
          // Controls at the bottom
          Column(
            children: [
              const Spacer(),
              
              // Semi-transparent background for controls
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Change background button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _showImageOptions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue.shade300,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          '背景画像を変更',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Image fit options
                    const Text(
                      '画像の表示方法',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFitOption('カバー', BoxFit.cover),
                        _buildFitOption('フィット', BoxFit.contain),
                        _buildFitOption('タイル', BoxFit.none),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Opacity slider
                    Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '背景画像の透明度',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          _opacity.toStringAsFixed(0),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.lightBlue.shade300,
                        inactiveTrackColor: Colors.grey.shade300,
                        thumbColor: Colors.lightBlue.shade400,
                        overlayColor: Colors.lightBlue.withValues(alpha: 0.2),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 15),
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: _opacity,
                        min: 0,
                        max: 100,
                        onChanged: (value) {
                          setState(() {
                            _opacity = value;
                          });
                        },
                        onChangeEnd: (value) {
                          _saveSettings();
                        },
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
  }
  
  Widget _buildFitOption(String label, BoxFit fit) {
    final isSelected = _imageFit == fit;
    return GestureDetector(
      onTap: () {
        setState(() {
          _imageFit = fit;
        });
        _saveSettings();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.lightBlue.shade300 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}