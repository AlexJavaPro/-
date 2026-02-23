import 'package:flutter/material.dart';

import 'features/security/app_lock_gate.dart';
import 'features/send/send_screen.dart';

class PhotoMailerApp extends StatelessWidget {
  const PhotoMailerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF246AF8);
    const skyBlue = Color(0xFF57CFE8);
    const accentRed = Color(0xFFFF4469);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.light,
      primary: primaryBlue,
      secondary: skyBlue,
      tertiary: accentRed,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ФотоПочта',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFEAF3FF),
        fontFamily: 'sans-serif',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.86),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const AppLockGate(child: SendScreen()),
    );
  }
}

