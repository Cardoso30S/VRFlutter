import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart';

import '../core/vr_config.dart';
import 'orientation_mapping.dart';

/// Head-tracking 3-DoF a partir do giroscopio + acelerometro.
///
/// ## Por que nao usar o `DeviceOrientationEvent` do navegador?
///
/// Dentro do WebView ele chega a ~30-40 Hz, ja filtrado pelo SO, com latencia
/// extra e exigindo `requestPermission()` no iOS. Lendo o sensor nativo em
/// `SensorInterval.gameInterval` (~50 Hz, ~20 ms) e fundindo aqui, a latencia
/// motion-to-photon cai bastante e ganhamos controle do filtro.
///
/// ## Algoritmo
///
/// Filtro complementar de Mahony (variante explicita do complementar
/// giroscopio+acelerometro):
///
/// 1. O giroscopio integra a orientacao (preciso no curto prazo, deriva no
///    longo prazo).
/// 2. O acelerometro fornece uma referencia absoluta de "para cima" quando o
///    modulo do vetor esta proximo de 1 g (ou seja, sem aceleracao linear
///    relevante). O erro entre a gravidade medida e a predita realimenta a
///    velocidade angular com ganho [VrConfig.gyroFilterKp].
/// 3. O termo integral [VrConfig.gyroFilterKi] estima o bias do giroscopio.
///
/// Pitch e roll ficam absolutos (sem deriva). O YAW **deriva** por nao haver
/// referencia absoluta - nao usamos magnetometro de proposito, pois dentro de
/// um visor com ima (a maioria dos Cardboard tem) a leitura fica inutil.
/// A correcao e o [recenter], exposto na UI como "Centralizar" (toque duplo).
///
/// Todo o estado interno e mantido em `double` primitivos: o filtro roda a
/// ~50 Hz e nao deve alocar objetos por amostra.
class HeadTracker {
  HeadTracker({required VrConfig config})
      : _config = config,
        _mapping = OrientationMapping(config.deviceOrientation);

  VrConfig _config;
  OrientationMapping _mapping;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Quaternion corpo -> mundo (mundo com +Y para cima, convencao Three.js).
  double _qx = 0.0, _qy = 0.0, _qz = 0.0, _qw = 1.0;

  // Bias estimado do giroscopio (rad/s, referencial do corpo).
  double _bx = 0.0, _by = 0.0, _bz = 0.0;

  // Ultima leitura do acelerometro (m/s^2, referencial do corpo).
  double _ax = 0.0, _ay = 0.0, _az = 0.0;
  bool _hasAccel = false;
  bool _initialized = false;

  // Offset de yaw aplicado no referencial do mundo (recentragem).
  double _yawOffset = 0.0;

  final Stopwatch _clock = Stopwatch();
  int _lastMicros = 0;

  bool _gyroAvailable = true;
  String? _lastError;

  /// `false` quando o aparelho nao expoe giroscopio; nesse caso a orientacao
  /// vem apenas da inclinacao do acelerometro (sem yaw).
  bool get gyroscopeAvailable => _gyroAvailable;

  /// Ultimo erro reportado pelos streams de sensores, se houver.
  String? get lastError => _lastError;

  /// `true` assim que a primeira amostra valida foi processada.
  bool get isReady => _initialized;

  /// Inicia a leitura dos sensores. Idempotente.
  void start() {
    if (_gyroSub != null || _accelSub != null) return;

    _clock
      ..reset()
      ..start();
    _lastMicros = _clock.elapsedMicroseconds;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      _onAccelerometer,
      onError: (Object e) => _lastError = 'accelerometer: $e',
      cancelOnError: false,
    );

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      _onGyroscope,
      onError: (Object e) {
        _gyroAvailable = false;
        _lastError = 'gyroscope: $e';
      },
      cancelOnError: false,
    );
  }

  /// Encerra as assinaturas dos sensores.
  Future<void> stop() async {
    await _gyroSub?.cancel();
    await _accelSub?.cancel();
    _gyroSub = null;
    _accelSub = null;
    _clock.stop();
  }

  /// Atualiza a configuracao em tempo real (ganhos do filtro e orientacao
  /// fisica do aparelho no visor).
  void updateConfig(VrConfig config) {
    if (config.deviceOrientation != _config.deviceOrientation) {
      _mapping = OrientationMapping(config.deviceOrientation);
    }
    _config = config;
  }

  /// Zera o yaw: a direcao para onde o usuario olha agora passa a ser o
  /// "norte" do mundo virtual. Chame apos calcar o visor na cabeca.
  void recenter() {
    final EulerAngles e = EulerAngles.fromQuaternion(cameraOrientation);
    _yawOffset -= e.yaw;
    _yawOffset = _wrapPi(_yawOffset);
  }

  // -------------------------------------------------------------------
  // Saidas
  // -------------------------------------------------------------------

  /// Orientacao do CORPO do aparelho em relacao ao mundo (Y para cima),
  /// ja com o offset de recentragem aplicado.
  Quaternion get bodyOrientation {
    // qYaw (mundo) * qBody
    final double half = _yawOffset * 0.5;
    final double sy = math.sin(half);
    final double cy = math.cos(half);
    // qYaw = (0, sy, 0, cy) em (x, y, z, w).
    final double x = cy * _qx + sy * _qz;
    final double y = cy * _qy + sy * _qw;
    final double z = cy * _qz - sy * _qx;
    final double w = cy * _qw - sy * _qy;
    return Quaternion(x, y, z, w)..normalize();
  }

  /// Orientacao da CAMERA 3D (referencial Three.js), pronta para ser enviada
  /// ao renderizador: `qCamera = qYaw * qBody * qAlign`.
  Quaternion get cameraOrientation => _mapping.toCamera(bodyOrientation);

  /// Angulos de Euler (YXZ) da camera, uteis para o gaze-walking e o HUD.
  EulerAngles get euler => EulerAngles.fromQuaternion(cameraOrientation);

  /// Vetor "para frente" da camera no mundo (`-Z` local rotacionado).
  Vector3 get forward => cameraOrientation.rotated(Vector3(0.0, 0.0, -1.0));

  // -------------------------------------------------------------------
  // Callbacks dos sensores
  // -------------------------------------------------------------------

  void _onAccelerometer(AccelerometerEvent event) {
    _ax = event.x;
    _ay = event.y;
    _az = event.z;
    _hasAccel = true;

    if (!_initialized) {
      _seedFromGravity();
      return;
    }
    // Sem giroscopio o acelerometro precisa dirigir o filtro sozinho.
    if (!_gyroAvailable) {
      final int now = _clock.elapsedMicroseconds;
      final double dt = ((now - _lastMicros) / 1e6).clamp(1e-4, 0.1);
      _lastMicros = now;
      _integrate(0.0, 0.0, 0.0, dt);
    }
  }

  void _onGyroscope(GyroscopeEvent event) {
    final int now = _clock.elapsedMicroseconds;
    final double dt = ((now - _lastMicros) / 1e6).clamp(1e-4, 0.1);
    _lastMicros = now;

    if (!_initialized) {
      if (_hasAccel) _seedFromGravity();
      return;
    }
    _integrate(event.x, event.y, event.z, dt);
  }

  // -------------------------------------------------------------------
  // Nucleo do filtro
  // -------------------------------------------------------------------

  /// Inicializa o quaternion com a rotacao minima que leva a gravidade medida
  /// ate `+Y` do mundo, evitando o "solavanco" inicial de convergencia.
  void _seedFromGravity() {
    final double n = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
    if (n < 1e-3) return;
    final double mx = _ax / n, my = _ay / n, mz = _az / n;

    // Rotacao minima que leva m ate up = (0, 1, 0):
    //   eixo = m x up = (-mz, 0, mx)
    //   w    = 1 + (m . up) = 1 + my
    final double axX = -mz;
    final double axY = 0.0;
    final double axZ = mx;
    final double w = 1.0 + my; // 1 + dot(m, up)

    if (w < 1e-6) {
      // m aponta exatamente para -Y: rotacao de 180 graus em torno de X.
      _qx = 1.0;
      _qy = 0.0;
      _qz = 0.0;
      _qw = 0.0;
    } else {
      _qx = axX;
      _qy = axY;
      _qz = axZ;
      _qw = w;
      _normalizeQuaternion();
    }
    _initialized = true;
  }

  /// Um passo do filtro complementar.
  ///
  /// [gx], [gy], [gz] em rad/s no referencial do corpo; [dt] em segundos.
  void _integrate(double gx, double gy, double gz, double dt) {
    double wx = gx, wy = gy, wz = gz;

    if (_hasAccel) {
      final double norm = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
      // Aceita apenas leituras proximas de 1 g: fora dessa janela ha
      // aceleracao linear (usuario andando/balancando) e a referencia de
      // gravidade seria enganosa.
      if (norm > 6.5 && norm < 13.0) {
        final double mx = _ax / norm, my = _ay / norm, mz = _az / norm;

        // Gravidade predita no referencial do corpo = R^T * (0,1,0),
        // isto e, a segunda LINHA da matriz de rotacao de q.
        final double px = 2.0 * (_qx * _qy + _qw * _qz);
        final double py = 1.0 - 2.0 * (_qx * _qx + _qz * _qz);
        final double pz = 2.0 * (_qy * _qz - _qw * _qx);

        // e = m x p  (leva o vetor predito em direcao ao medido)
        final double ex = my * pz - mz * py;
        final double ey = mz * px - mx * pz;
        final double ez = mx * py - my * px;

        final double ki = _config.gyroFilterKi;
        if (ki > 0.0) {
          _bx += ex * ki * dt;
          _by += ey * ki * dt;
          _bz += ez * ki * dt;
          // Trava o bias em +-0.1 rad/s (~5.7 graus/s), acima disso seria
          // divergencia e nao bias real.
          _bx = _bx.clamp(-0.1, 0.1);
          _by = _by.clamp(-0.1, 0.1);
          _bz = _bz.clamp(-0.1, 0.1);
        }

        final double kp = _config.gyroFilterKp;
        wx += ex * kp + _bx;
        wy += ey * kp + _by;
        wz += ez * kp + _bz;
      }
    }

    // Integracao pelo mapa exponencial (preserva a norma mesmo em rotacoes
    // rapidas, ao contrario da forma linearizada q += 0.5*q*w*dt).
    final double omega = math.sqrt(wx * wx + wy * wy + wz * wz);
    if (omega < 1e-9) return;

    final double theta = omega * dt * 0.5;
    final double s = math.sin(theta) / omega;
    final double dqx = wx * s;
    final double dqy = wy * s;
    final double dqz = wz * s;
    final double dqw = math.cos(theta);

    // q = q * dq  (dq esta no referencial do corpo => multiplicacao a direita)
    final double nx = _qw * dqx + _qx * dqw + _qy * dqz - _qz * dqy;
    final double ny = _qw * dqy - _qx * dqz + _qy * dqw + _qz * dqx;
    final double nz = _qw * dqz + _qx * dqy - _qy * dqx + _qz * dqw;
    final double nw = _qw * dqw - _qx * dqx - _qy * dqy - _qz * dqz;

    _qx = nx;
    _qy = ny;
    _qz = nz;
    _qw = nw;
    _normalizeQuaternion();
  }

  void _normalizeQuaternion() {
    final double n =
        math.sqrt(_qx * _qx + _qy * _qy + _qz * _qz + _qw * _qw);
    if (n < 1e-9) {
      _qx = 0.0;
      _qy = 0.0;
      _qz = 0.0;
      _qw = 1.0;
      return;
    }
    final double inv = 1.0 / n;
    _qx *= inv;
    _qy *= inv;
    _qz *= inv;
    _qw *= inv;
  }

  static double _wrapPi(double a) {
    double v = a;
    while (v > math.pi) {
      v -= 2 * math.pi;
    }
    while (v < -math.pi) {
      v += 2 * math.pi;
    }
    return v;
  }
}
