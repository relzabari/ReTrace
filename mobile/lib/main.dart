import 'package:flutter/material.dart';
import 'features/setup/setup_page.dart';

void main() => runApp(const PrototypeApp());

class PrototypeApp extends StatelessWidget {
  const PrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Exercise Tracker Prototype',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      locale: const Locale('he'),
      home: const Directionality(textDirection: TextDirection.rtl, child: SetupPage()),
    );
  }
}
