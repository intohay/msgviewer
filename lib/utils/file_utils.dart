import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:csv/csv.dart';
import '../utils/database_helper.dart';
import 'helper.dart';



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
    
    for (final file in archive) {
      final relativePath = file.name.replaceFirst('$rootFolderName/', '');
      final filePath = join(extractPath, relativePath);

      if (file.isFile && !file.name.contains('__MACOSX')) {
        final data = file.content as List<int>;
        File(filePath)..createSync(recursive: true)..writeAsBytesSync(data);
      }
    }

    final mediaPath = join(extractPath, 'media');
    Directory(mediaPath).createSync(recursive: true);

    final input = File(join(extractPath, "$rootFolderName.csv")).openRead();
    final fields = await input
        .transform(utf8.decoder)
        .transform(const CsvToListConverter(eol: '\n', fieldDelimiter: ','))
        .toList();

    fields.removeAt(0); // ヘッダーを削除
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
          "name": rootFolderName,
          "date": date,
          "text": null,
          "filename": null,
          "is_favorite": false,
        });

        if (type == 0 && textExtensions.contains(".$extension")) {
          groupedEntries[id]!["text"] = File(filePath).readAsStringSync();
        } else if ((type == 1 && imageExtensions.contains(".$extension")) ||
                  (type == 2 && videoExtensions.contains(".$extension")) ||
                  (type == 3 && audioExtensions.contains(".$extension"))) {
          
            final mediaFilePath = join(mediaPath, basename(filePath));
            File(filePath).copySync(mediaFilePath);
            groupedEntries[id]!["filename"] = basename(filePath); 
        }
      }
    }

    for (var entry in groupedEntries.values) {
      extractedData.add([
        entry["id"],
        entry["name"],
        entry["date"],
        entry["text"] ?? "",
        entry["filename"] ?? "",
        false,
      ]);
    }

    if (extractedData.isNotEmpty) {
      await dbHelper.insertData(extractedData);
    }

    return extractedName;
  }


}
