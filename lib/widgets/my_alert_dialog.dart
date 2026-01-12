import 'package:flutter/material.dart';

class MyAlertDialog extends StatelessWidget {
  const MyAlertDialog({
    super.key,
    required this.onpressed,
    required this.text,
    required this.title,
    required this.content,
  });

  final void Function()? onpressed;
  final String text;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        title,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      content: Text(content, style: TextStyle(fontSize: 18)),
      actions: [
        MaterialButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(onPressed: onpressed, child: Text(text)),
      ],
    );
  }
}
