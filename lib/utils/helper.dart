import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';



String formatDateTimeForDatabase(String inputDateTime) {
  DateTime parsedDateTime;

  if (RegExp(r'^\d{4}-\d{4}-\d{6}$').hasMatch(inputDateTime)) {
    // `2024-1217-161129` の形式ならそのままパース
    parsedDateTime = DateTime.parse(
        "${inputDateTime.substring(0, 4)}-${inputDateTime.substring(5, 7)}-${inputDateTime.substring(7, 9)} "
        "${inputDateTime.substring(10, 12)}:${inputDateTime.substring(12, 14)}:${inputDateTime.substring(14, 16)}");
  } else if (RegExp(r'^\d{14}$').hasMatch(inputDateTime)) {
    // `20241217161129` の形式ならパースして9時間足す
    parsedDateTime = DateTime.parse(
        "${inputDateTime.substring(0, 4)}-${inputDateTime.substring(4, 6)}-${inputDateTime.substring(6, 8)} "
        "${inputDateTime.substring(8, 10)}:${inputDateTime.substring(10, 12)}:${inputDateTime.substring(12, 14)}")
        .add(const Duration(hours: 9));
  } else {
    throw FormatException("Invalid datetime format: $inputDateTime");
  }

  return parsedDateTime.toIso8601String(); // SQLiteのDATETIME型に適した形式で返す
}




// ヘルパー関数: サムネイル生成
Future<void> generateThumbnail(String inputPath, String outputPath) async {
  final result = await FlutterImageCompress.compressAndGetFile(
    inputPath,
    outputPath,
    quality: 50, // 品質を調整（低いほど軽量）
    minWidth: 300, // 幅300px以下に縮小
    minHeight: 300, // 高さ300px以下に縮小
  );
  if (result == null) {
    throw Exception("Failed to generate thumbnail for $inputPath");
  }
}

// ヘルパー関数: 動画のサムネイル生成
Future<String> generateVideoThumbnail(String videoFilePath, String outputThumbnailPath) async {
  final String? thumbPath = await VideoThumbnail.thumbnailFile(
    video: videoFilePath,
    thumbnailPath: outputThumbnailPath,
    imageFormat: ImageFormat.JPEG,
    maxHeight: 400, // 必要に応じてサイズを調整
    quality: 75,    // 品質（数値が低いほど軽量）
  );
  if (thumbPath == null) {
    throw Exception("Failed to generate video thumbnail for $videoFilePath");
  }
  return thumbPath;
}

String replacePlaceHolders(String text, String callMeName) {
    String modifiedText = text.replaceAll("%%%", callMeName).replaceAll("％％％", callMeName);

    return modifiedText;
  }