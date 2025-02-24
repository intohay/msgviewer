import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppConfig {
  static late final String appDocumentsDirectory;

  static Future<void> initialize() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    appDocumentsDirectory = dir.path;
  }
}


