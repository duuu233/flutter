import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:BoltStar/src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF7EDE2),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Color(0xFFE5DED4),
    ),
  );
  runApp(const FrameFlowApp());
}
