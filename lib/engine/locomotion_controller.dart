import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../core/vr_config.dart';
import '../sensors/head_tracker.dart';
import '../sensors/orientation_mapping.dart';
import 'vr_state.dart';
import 'world_bounds.dart';

/// Loop de fisica/locomocao do jogador.
///
/// ## Passo fixo
///
/// O `Ticker` do Flutter entrega `dt` variavel (e ate 200 ms depois de um GC
/// ou de uma troca de app). Integrar movimento com `dt` variavel produz
/// atravessamento de colisores e "teleporte". Por isso acumulamos o tempo e
/// integramos em passos fixos de [_fixedStep], no maximo [_maxSubSteps] por
/// frame (evita a espiral da morte).
///
/// ## Modelo de movimento
///
/// Velocidade em direcao a um alvo com aceleracao limitada e amortecimento
/// exponencial. Nada de gravidade/pulo: em VR movel isso e a receita para
/// enjoo. A direcao "frente" vem do YAW da cabeca projetado no plano XZ
/// (locomocao head-directed, o padrao do Cardboard).
class LocomotionController {
  LocomotionController({
    required VrConfig config,
    required HeadTracker headTracker,
  })  : _config = config,
        _head = headTracker,
        _bounds = WorldBounds(radius: config.worldRadius) {
    _position.setValues(0.0, config.eyeHeight, 6.0);
  }

  VrConfig _config;
  final HeadTracker _head;
  WorldBounds _bounds;

  static const double _fixedStep = 1.0 / 120.0;
  static const int _maxSubSteps = 6;

  final Vector3 _position = Vector3.zero();
  final Vector2 _velocity = Vector2.zero();
  final List<double> _scratch = <double>[0.0, 0.0];

  double _accumulator = 0.0;
  double _bobPhase = 0.0;
  double _headBob = 0.0;

  LocomotionInput _input = LocomotionInput.idle;

  /// `true` enquanto o usuario mantem o toque na tela (gatilho do Cardboard
  /// ou toque simples), o que forca o andar no modo gaze.
  bool triggerHeld = false;

  WorldBounds get bounds => _bounds;
  Vector3 get position => _position;
  double get speed => _velocity.length;
  LocomotionInput get input => _input;

  /// Define o vetor de entrada (joystick, gamepad ou gaze).
  set input(LocomotionInput value) => _input = value.clampedToUnitCircle();

  void updateConfig(VrConfig config) {
    if (config.worldRadius != _config.worldRadius) {
      // Trocar o raio do mapa descarta os colisores; o WebView os reenvia no
      // proximo `sceneReady`.
      _bounds = WorldBounds(radius: config.worldRadius);
    }
    _config = config;
  }

  /// Reposiciona o jogador (spawn / "voltar ao inicio").
  void teleport(double x, double z) {
    _position.setValues(x, _config.eyeHeight, z);
    _velocity.setZero();
  }

  /// Avanca a simulacao em [dt] segundos e devolve o estado do frame.
  VrFrameState step(double dt) {
    _accumulator += dt.clamp(0.0, 0.25);
    int steps = 0;
    while (_accumulator >= _fixedStep && steps < _maxSubSteps) {
      _integrate(_fixedStep);
      _accumulator -= _fixedStep;
      steps++;
    }
    if (steps == _maxSubSteps) {
      // Descarta o atraso residual em vez de tentar recuperar (spiral of death).
      _accumulator = 0.0;
    }

    return VrFrameState(
      position: Vector3(
        _position.x,
        _position.y + _headBob,
        _position.z,
      ),
      orientation: _head.cameraOrientation,
      speed: _velocity.length,
      moving: _velocity.length2 > 0.01,
      headBob: _headBob,
    );
  }

  // -------------------------------------------------------------------

  void _integrate(double dt) {
    final EulerAngles e = _head.euler;
    final LocomotionInput resolved = _resolveInput(e);

    // Base horizontal derivada do yaw da cabeca.
    // yaw = 0 -> olhando para -Z. Portanto:
    //   frente = (-sin(yaw), 0, -cos(yaw))
    //   direita = ( cos(yaw), 0, -sin(yaw))
    final double sy = math.sin(e.yaw);
    final double cy = math.cos(e.yaw);
    final double fx = -sy, fz = -cy;
    final double rx = cy, rz = -sy;

    final double maxSpeed =
        resolved.running ? _config.runSpeed : _config.walkSpeed;

    final double targetX =
        (fx * resolved.forward + rx * resolved.strafe) * maxSpeed;
    final double targetZ =
        (fz * resolved.forward + rz * resolved.strafe) * maxSpeed;

    if (resolved.isActive) {
      // Aproximacao da velocidade alvo com aceleracao limitada.
      final double dvx = targetX - _velocity.x;
      final double dvz = targetZ - _velocity.y;
      final double dvLen = math.sqrt(dvx * dvx + dvz * dvz);
      final double maxDelta = _config.acceleration * dt;
      if (dvLen <= maxDelta || dvLen < 1e-9) {
        _velocity.setValues(targetX, targetZ);
      } else {
        final double k = maxDelta / dvLen;
        _velocity.setValues(
          _velocity.x + dvx * k,
          _velocity.y + dvz * k,
        );
      }
    } else {
      // Amortecimento exponencial: independente da taxa de quadros.
      final double decay = math.exp(-_config.damping * dt);
      _velocity.scale(decay);
      if (_velocity.length2 < 1e-4) _velocity.setZero();
    }

    // Integracao + colisao.
    final double nx = _position.x + _velocity.x * dt;
    final double nz = _position.z + _velocity.y * dt;
    _bounds.resolve(nx, nz, _scratch);

    // Se a colisao "comeu" o deslocamento, zera a componente correspondente
    // para o jogador nao ficar grudado vibrando contra a arvore.
    final double appliedX = _scratch[0] - _position.x;
    final double appliedZ = _scratch[1] - _position.z;
    if (appliedX.abs() < 1e-5) _velocity.x = 0.0;
    if (appliedZ.abs() < 1e-5) _velocity.y = 0.0;

    _position.x = _scratch[0];
    _position.z = _scratch[1];
    _position.y = _config.eyeHeight;

    _updateHeadBob(dt);
  }

  /// Converte o modo de locomocao configurado em um vetor de entrada.
  LocomotionInput _resolveInput(EulerAngles e) {
    switch (_config.locomotionMode) {
      case LocomotionMode.joystick:
        // Toque na tela vira "correr" quando ja ha input do joystick.
        if (_input.isActive) {
          return LocomotionInput(
            strafe: _input.strafe,
            forward: _input.forward,
            running: triggerHeld || _input.running,
          );
        }
        return LocomotionInput.idle;

      case LocomotionMode.gaze:
        // Opcao A: olhar abaixo do limiar OU manter o toque -> anda para frente.
        final bool lookingDown = e.pitch < _config.gazeWalkPitchThresholdRad;
        if (!lookingDown && !triggerHeld) return LocomotionInput.idle;

        // Rampa suave entre o limiar e 20 graus abaixo dele: evita o
        // "liga/desliga" brusco que causa desconforto.
        double intensity = 1.0;
        if (lookingDown) {
          final double over =
              (_config.gazeWalkPitchThresholdRad - e.pitch) / (20 * math.pi / 180);
          intensity = over.clamp(0.25, 1.0);
        }
        return LocomotionInput(forward: intensity, running: triggerHeld && lookingDown);
    }
  }

  void _updateHeadBob(double dt) {
    final double amp = _config.headBobAmplitude;
    if (amp <= 0.0) {
      _headBob = 0.0;
      return;
    }
    final double v = _velocity.length;
    if (v > 0.05) {
      _bobPhase += dt * _config.headBobFrequency * 2 * math.pi * (v / _config.walkSpeed);
      _headBob = math.sin(_bobPhase) * amp * (v / _config.walkSpeed).clamp(0.0, 1.0);
    } else {
      // Retorna suavemente ao repouso.
      _headBob *= math.exp(-8.0 * dt);
      if (_headBob.abs() < 1e-4) {
        _headBob = 0.0;
        _bobPhase = 0.0;
      }
    }
  }
}
