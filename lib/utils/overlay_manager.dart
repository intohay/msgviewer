import 'package:flutter/material.dart';

/// グローバルなオーバーレイ管理クラス
/// アプリ全体で同時に一つのオーバーレイのみを表示するように制御
class OverlayManager {
  static final OverlayManager _instance = OverlayManager._internal();
  factory OverlayManager() => _instance;
  OverlayManager._internal();

  OverlayEntry? _currentOverlay;
  bool _isShowingOverlay = false;

  /// オーバーレイが表示中かどうか
  bool get isShowingOverlay => _isShowingOverlay;

  /// オーバーレイを表示
  /// 既に表示中の場合はfalseを返す
  bool showOverlay(BuildContext context, OverlayEntry overlay) {
    if (_isShowingOverlay) {
      return false;
    }

    // 既存のオーバーレイがあれば削除
    _currentOverlay?.remove();
    _currentOverlay = null;

    _currentOverlay = overlay;
    _isShowingOverlay = true;
    Overlay.of(context).insert(overlay);
    return true;
  }

  /// オーバーレイを閉じる
  void closeOverlay() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    _isShowingOverlay = false;
  }

  /// 強制的に全てのオーバーレイをクリア
  void clearAll() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    _isShowingOverlay = false;
  }
}