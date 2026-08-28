import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Pacote de estado enviado ao renderizador a cada frame.
///
/// E deliberadamente pequeno e sem alocacao de `Map`/`List` na serializacao:
/// vira uma unica chamada JS com argumentos numericos, o caminho mais barato
/// atraves da ponte Flutter <-> WebView.
class VrFrameState {
  const VrFrameState({
    required this.position,
    required this.orientation,
    required this.speed,
    required this.moving,
    required this.headBob,
  });

  /// Posicao dos olhos no mundo (metros, Y ja inclui a altura dos olhos).
  final Vector3 position;

  /// Orientacao da camera no referencial Three.js.
  final Quaternion orientation;

  /// Modulo da velocidade horizontal (m/s), usado para efeitos na cena.
  final double speed;

  /// `true` quando ha locomocao ativa (usado para o reticulo e o audio).
  final bool moving;

  /// Deslocamento vertical do head bob ja aplicado em [position].
  final double headBob;

  static final VrFrameState zero = VrFrameState(
    position: Vector3(0, 1.68, 0),
    orientation: Quaternion.identity(),
    speed: 0,
    moving: false,
    headBob: 0,
  );

  /// Serializa como lista de argumentos para `VRB.state(...)`.
  ///
  /// Precisao fixa em 4 casas: o suficiente para 0.1 mm e mantem a string
  /// curta (a ponte JS custa por byte).
  String toJsArgs() {
    final StringBuffer b = StringBuffer();
    b.write(position.x.toStringAsFixed(4));
    b.write(',');
    b.write(position.y.toStringAsFixed(4));
    b.write(',');
    b.write(position.z.toStringAsFixed(4));
    b.write(',');
    b.write(orientation.x.toStringAsFixed(5));
    b.write(',');
    b.write(orientation.y.toStringAsFixed(5));
    b.write(',');
    b.write(orientation.z.toStringAsFixed(5));
    b.write(',');
    b.write(orientation.w.toStringAsFixed(5));
    b.write(',');
    b.write(speed.toStringAsFixed(3));
    b.write(',');
    b.write(moving ? '1' : '0');
    return b.toString();
  }
}

/// Vetor de entrada de locomocao normalizado.
///
/// [strafe] = eixo lateral (-1 esquerda, +1 direita).
/// [forward] = eixo frontal (-1 tras, +1 frente).
class LocomotionInput {
  const LocomotionInput({
    this.strafe = 0.0,
    this.forward = 0.0,
    this.running = false,
  });

  final double strafe;
  final double forward;
  final bool running;

  static const LocomotionInput idle = LocomotionInput();

  bool get isActive => strafe.abs() > 0.001 || forward.abs() > 0.001;

  /// Limita o modulo a 1 para que o movimento na diagonal nao fique mais
  /// rapido do que na horizontal.
  LocomotionInput clampedToUnitCircle() {
    final double len2 = strafe * strafe + forward * forward;
    if (len2 <= 1.0) return this;
    final double inv = 1.0 / math.sqrt(len2);
    return LocomotionInput(
      strafe: strafe * inv,
      forward: forward * inv,
      running: running,
    );
  }
}
