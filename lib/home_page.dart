import 'package:flutter/material.dart';
import 'talk_page.dart';
import 'dialogs/file_picker_dialog.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: const Text('hoge岸piyoリ'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => TalkPage()));
            }
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(context: context, builder: (context) => FilePickerDialog());
        },
        tooltip: 'Import Zip File',
        child: const Icon(Icons.add),
      ),
    );
  }
}

