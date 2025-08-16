import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:csv/csv.dart';
import '../utils/database_helper.dart';

class FilePickerDialog extends StatefulWidget {
  const FilePickerDialog({super.key});

  @override
  FilePickerDialogState createState() => FilePickerDialogState();
}

class FilePickerDialogState extends State<FilePickerDialog> {
  String? zipFilePath;
  final dbHelper = DatabaseHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Talk Data'),
        leading: IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _processZip(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () => _pickFile(context),
              child: const Text('Pick ZIP File'),
            ),
            if (zipFilePath != null) Text('Selected ZIP File: $zipFilePath'),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null) {
      setState(() {
        zipFilePath = result.files.single.name;
      });
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected.')),
        );
      }
    }
  }

  Future<void> _processZip(BuildContext context) async {
    if (zipFilePath == null) return;

    final bytes = File(zipFilePath!).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final directory = await getApplicationDocumentsDirectory();

    // ZIPフォルダ名を取得（最初のフォルダ名）
    String? rootFolderName;
    for (final file in archive) {
      final parts = file.name.split('/');
      if (parts.isNotEmpty) {
        debugPrint(parts.first);
        rootFolderName = parts.first;
        break;
      }
    }

    if (rootFolderName == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid ZIP structure.')),
        );
      }
      return;
    }

    final extractPath = join(directory.path, rootFolderName);
    debugPrint('Extracting to: $extractPath');
    Directory(extractPath).createSync(recursive: true);


    String? csvFilePath;

    // ZIPファイルの中のCSVファイルを抽出
    for (final file in archive) {
      
      final filePath = join(extractPath, file.name.replaceFirst('$rootFolderName/', ''));

      if (file.isFile && !file.name.contains('__MACOSX')) {
        final data = file.content as List<int>;
        File(filePath)..createSync(recursive: true)..writeAsBytesSync(data);

        if (file.name.endsWith('.csv')) {
          csvFilePath = filePath;
        }
      }
    }

    debugPrint('CSV file: $csvFilePath');

    if (csvFilePath != null) {
      final input = File(csvFilePath).openRead();
      final fields = await input
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(eol: '\n', fieldDelimiter: ','))
          .toList();

      fields.removeAt(0); // ヘッダーを削除
      await dbHelper.insertData(fields);
    }

    
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}