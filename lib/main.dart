import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

/// Ponto de entrada.
///
/// O bloqueio de orientacao acontece aqui (e nao so na tela VR) para que
/// nenhuma rotacao de layout ocorra durante o primeiro frame, o que causaria
/// um redimensionamento caro do contexto WebGL.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const VrDinoApp());
}
