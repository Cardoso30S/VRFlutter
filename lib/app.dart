import 'package:flutter/material.dart';

import 'ui/vr_screen.dart';

/// Raiz do app. Tema escuro fixo: qualquer luz extra na tela vaza pelas
/// bordas das lentes e reduz o contraste percebido dentro do visor.
class VrDinoApp extends StatelessWidget {
  const VrDinoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VR Dino Cardboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6FCF97),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF06080C),
      ),
      home: const Scaffold(
        backgroundColor: Color(0xFF06080C),
        body: VrScreen(),
      ),
    );
  }
}
