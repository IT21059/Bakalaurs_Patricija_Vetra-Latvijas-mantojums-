import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/map_pages.dart';
import 'home.dart';
//lietotnes palaišanas sākums
void main() {
  runApp(const MyApp()); //startē flutter lietotni
}

//pie StatelessWidget labošanas tika izmantots MI palīdzība
class MyApp extends StatelessWidget {
  const MyApp({super.key});

//šajā funkcijā tika izmantota Mi palīdzība labojumam
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, //noņem debug ekrāna augšmalā
      home: MapPage(), //sākuma lapa
      theme: ThemeData(fontFamily: 'Poppins'), //lietotnes dizaina stils un fonts
    );
  }
} 