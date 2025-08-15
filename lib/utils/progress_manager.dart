import 'dart:async';

/// 進捗管理クラス
class ProgressManager {
  final StreamController<ProgressData> _progressController = StreamController<ProgressData>.broadcast();
  
  Stream<ProgressData> get progressStream => _progressController.stream;
  
  void updateProgress({
    required double progress,
    required String message,
    String? detail,
  }) {
    if (!_progressController.isClosed) {
      _progressController.add(ProgressData(
        progress: progress.clamp(0.0, 1.0),
        message: message,
        detail: detail,
      ));
    }
  }
  
  void dispose() {
    _progressController.close();
  }
}

/// 進捗データクラス
class ProgressData {
  final double progress; // 0.0 ~ 1.0
  final String message;
  final String? detail;
  
  ProgressData({
    required this.progress,
    required this.message,
    this.detail,
  });
  
  int get percentage => (progress * 100).round();
}