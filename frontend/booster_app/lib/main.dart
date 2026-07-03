import 'package:flutter/material.dart';
import 'theme/booster_theme.dart';
import 'screens/auth/login_screen.dart';

void main() => runApp(const BoosterApp());

class BoosterApp extends StatelessWidget {
  const BoosterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Booster',
      debugShowCheckedModeBanner: false,
      theme: BoosterTheme.light(),
      home: const LoginScreen(),
    );
  }
}
