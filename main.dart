import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/map_pages.dart';
import 'home.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapPage(), 
      theme: ThemeData(fontFamily: 'Poppins'),
    );
  }
} 