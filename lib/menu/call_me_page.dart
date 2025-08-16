import 'package:flutter/material.dart';
import '../utils/database_helper.dart';

class CallMePage extends StatefulWidget {
  final String name;
  final String? currentCallMe;
  final Function(String) onCallMeChanged;

  const CallMePage({super.key, required this.name, this.currentCallMe, required this.onCallMeChanged});

  @override
  CallMePageState createState() => CallMePageState();
}

class CallMePageState extends State<CallMePage> {
  final TextEditingController _controller = TextEditingController();
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.currentCallMe ?? "";
  }

  Future<void> _saveCallMe() async {
    final newCallMe = _controller.text.trim();
    if (newCallMe.isNotEmpty) {
      await dbHelper.setCallMeName(widget.name, newCallMe);
      widget.onCallMeChanged(newCallMe);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("呼ばれたい名前を設定")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "呼ばれたい名前",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveCallMe,
              child: const Text("保存"),
            ),
          ],
        ),
      ),
    );
  }
}
