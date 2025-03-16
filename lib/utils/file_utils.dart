import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:csv/csv.dart';
import '../utils/database_helper.dart';
import 'helper.dart';

import 'package:path/path.dart' as p;

class FileManager {
  final DatabaseHelper dbHelper;

  FileManager(this.dbHelper);

  /// **ZIPファイルを選択する**
  Future<String?> pickZipFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null) {
      return result.files.single.path!;
    }
    return null;
  }

   /// **ZIPを解凍してデータベースに保存**
  Future<String?> processZip(String zipFilePath) async {
    final bytes = File(zipFilePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final directory = await getApplicationDocumentsDirectory();

    // ZIPフォルダ名を取得
    String? rootFolderName;
    for (final file in archive) {
      final parts = file.name.split('/');
      if (parts.isNotEmpty) {
        rootFolderName = parts.first;
        break;
      }
    }

    if (rootFolderName == null) {
      throw Exception('Invalid ZIP structure.');
    }

    final extractPath = join(directory.path, rootFolderName);
    Directory(extractPath).createSync(recursive: true);

    // ZIP内のCSVファイルを探す
    bool hasCsvFile = false;
    String? csvFilePath;
    for (final file in archive) {
      if (file.isFile && file.name.endsWith('.csv')) {
        hasCsvFile = true;
        csvFilePath = file.name;
        break;
      }
    }

    if (hasCsvFile && csvFilePath != null) {
      // **CSVがある場合の処理**
      return await _processWithCsv(archive, extractPath, rootFolderName);
    } else {
      // **CSVがない場合の処理**
      return await _processWithoutCsv(archive, extractPath, rootFolderName);
    }
  }

  /// **CSVがある場合の処理**
  Future<String?> _processWithCsv(Archive archive, String extractPath, String rootFolderName) async {
    String? extractedName;
    
    // ZIP内の各ファイルを解凍し、サムネイルを生成
    for (final file in archive) {
      final relativePath = file.name.replaceFirst('$rootFolderName/', '');
      final filePath = join(extractPath, relativePath);

      if (file.isFile && !file.name.contains('__MACOSX')) {
        final data = file.content as List<int>;
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);

        if (file.name.endsWith('.jpg')) {
          final thumbFilePath = filePath.replaceFirst('.jpg', '_thumb.jpg');
          try {
            await generateThumbnail(filePath, thumbFilePath);
          } catch (e) {
            throw Exception("Failed to generate thumbnail for $filePath: $e");
          }
        } else if (file.name.endsWith('.mp4') || file.name.contains("_2_")) {
          final thumbFilePath = filePath.replaceFirst('.mp4', '_thumb.jpg');
          try {
            await generateVideoThumbnail(filePath, thumbFilePath);
          } catch (e) {
            throw Exception("Failed to generate video thumbnail for $filePath: $e");
          }
        }
      }
    }

    // mediaフォルダを作成（ここではCSV用に、後でパスを作るために利用）
    final mediaPath = join(extractPath, 'media');
    Directory(mediaPath).createSync(recursive: true);

    // CSVを読み込み、パース
    final input = File(join(extractPath, "$rootFolderName.csv")).openRead();
    final fields = await input
        .transform(utf8.decoder)
        .transform(const CsvToListConverter(eol: '\n', fieldDelimiter: ','))
        .toList();

    fields.removeAt(0); // ヘッダーを削除

    // CSVの各行の4列目にあるファイル名を、mediaフォルダ内のフルパスに変換し、
    // さらに5列目にサムネイルのフルパスを挿入する
    for (var row in fields) {
      if (row.length > 4 && row[4] is String && (row[4] as String).isNotEmpty) {
        final filename = row[4] as String;
        // メディアファイルのフルパス
        final fullFilePath = join(mediaPath, filename);
        // CSVの対象列を更新
        row[4] = fullFilePath;
        
        String thumb = "";
        if (filename.endsWith('.jpg')) {
          thumb = filename.replaceFirst('.jpg', '_thumb.jpg');
        } else if (filename.endsWith('.mp4')) {
          thumb = filename.replaceFirst('.mp4', '_thumb.jpg');
        }
        // サムネイルのフルパス
        final fullThumbPath = join(mediaPath, thumb);
        // 既存の5番目の要素の前にサムネイルパスを挿入（他の列は右にずれる）
        row.insert(5, fullThumbPath);
      } else {
        // ファイル名がなければ、サムネイルは空文字として挿入
        row.insert(5, "");
      }
    }

    await dbHelper.insertData(fields);

    if (fields.isNotEmpty) {
      extractedName = fields[0][1];
    }

    return extractedName;
  }

  /// **CSVなしZIPの処理**
  Future<String?> _processWithoutCsv(Archive archive, String extractPath, String rootFolderName) async {
    List<List<dynamic>> extractedData = [];
    String? extractedName;

    final Set<String> textExtensions = {'.txt'};
    final Set<String> imageExtensions = {'.jpg', '.jpeg', '.png'};
    final Set<String> videoExtensions = {'.mp4'};
    final Set<String> audioExtensions = {'.mp4'};

    // mediaフォルダを作成
    final mediaPath = join(extractPath, 'media');
    Directory(mediaPath).createSync(recursive: true);

    Map<String, Map<String, dynamic>> groupedEntries = {};
    for (final file in archive) {
      final relativePath = file.name.replaceFirst('$rootFolderName/', '');
      final filePath = join(extractPath, relativePath); // ZIP解凍時の元のパス

      if (file.isFile && !file.name.contains('__MACOSX')) {
        final data = file.content as List<int>;
        File(filePath)..createSync(recursive: true)..writeAsBytesSync(data);

        final RegExp regex = RegExp(r'(\d+)_(\d)_(\d{14})\.(txt|jpg|jpeg|png|mp4|m4a)');
        final match = regex.firstMatch(file.name);
        if (match == null) continue;

        final String id = match.group(1)!;
        final int type = int.parse(match.group(2)!);
        final String date = match.group(3)!;


        final String extension = match.group(4)!;

        if (extractedName == null) extractedName = rootFolderName;

        groupedEntries.putIfAbsent(id, () => {
          "id": id,
          "name": rootFolderName, // メンバーの名前
          "date": date,
          "text": null,
          "filepath": null,
          "thumb_filepath": null,
          "is_favorite": false,
        });

        if (((type == 0 || type == 1) && textExtensions.contains(".$extension"))) {
          groupedEntries[id]!["text"] = File(filePath).readAsStringSync();

        } else if (type == 1 && imageExtensions.contains(".$extension")) {
          final mediaFilePath = join(mediaPath, p.basename(filePath));
          File(filePath).copySync(mediaFilePath);
          
          groupedEntries[id]!["filepath"] = mediaFilePath;

          final thumbFileName = p.basenameWithoutExtension(filePath) + "_thumb.$extension";
          final thumbFilePath = join(mediaPath, thumbFileName);
          try {
            await generateThumbnail(mediaFilePath, thumbFilePath);
            groupedEntries[id]!["thumb_filepath"] = thumbFilePath;
          } catch (e) {
            throw Exception("Failed to generate thumbnail for $mediaFilePath: $e");
          }
        

        } else if(type == 2 && videoExtensions.contains(".$extension")){
          final mediaFilePath = p.join(mediaPath, p.basename(filePath));
          File(filePath).copySync(mediaFilePath);
          groupedEntries[id]!["filepath"] = mediaFilePath;

          final thumbFileName = p.basenameWithoutExtension(filePath) + "_thumb.jpg";
          final thumbFilePath = p.join(mediaPath, thumbFileName);
          try {
            await generateVideoThumbnail(mediaFilePath, thumbFilePath);
            groupedEntries[id]!["thumb_filepath"] = thumbFilePath;
          } catch (e) {
            throw Exception("Failed to generate video thumbnail for $mediaFilePath: $e");
          }

        } else if (type == 3 && audioExtensions.contains(".$extension")) {
          
            final mediaFilePath = join(mediaPath, basename(filePath));
            File(filePath).copySync(mediaFilePath);
            groupedEntries[id]!["filepath"] = mediaFilePath; 
        }
      }
    }

    for (var entry in groupedEntries.values) {
      extractedData.add([
        entry["id"],
        entry["name"],
        entry["date"],
        entry["text"] ?? "",
        entry["filepath"],
        entry["thumb_filepath"],
        false,
      ]);
    }

    if (extractedData.isNotEmpty) {
      await dbHelper.insertData(extractedData);
    }

    return extractedName;
  }


}
