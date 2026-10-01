import 'package:flutter/material.dart';

import 'floating_text_tasks.dart';

void main() => runApp(const FloatingTextApp());

class FloatingTextApp extends StatelessWidget {
  const FloatingTextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const FloatingTextTasks(
        title: 'September 29',
        tasks: [
          'Review project brief',
          'Check the mailbox',
          'Finish reading notes',
          'Call design partner',
          'Send weekly update',
          'Water the plants',
          'Book dentist appointment',
          'Plan weekend groceries',
        ],
      ),
    );
  }
}
