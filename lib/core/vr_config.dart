import 'dart:math' as math;

/// Orientacao fisica em que o aparelho e encaixado no visor Cardboard.
///
/// O SDK de sensores sempre reporta valores no referencial "natural" (retrato)
/// do aparelho, independentemente da orientacao da UI. Por isso precisamos
/// saber como a tela foi girada para converter o referencial do corpo do
/// aparelho no referencial da camera 3D. Ver [OrientationMapping].
enum VrDeviceOrientation {
  /// Topo do aparelho apontando para a ESQUERDA do usuario.
  landscapeLeft,

  /// Topo do aparelho apontando para a DIREITA do usuario.
  landscapeRight,
}

/// Modo de locomocao ativo.
enum LocomotionMode {
  /// Opcao A: anda para frente enquanto o usuario olha para baixo
  /// (abaixo de [VrConfig.gazeWalkPitchThreshold]) ou mantem o toque na tela.
  gaze,

  /// Opcao B: joystick virtual (arraste em qualquer ponto da tela) ou
  /// gamepad Bluetooth mapeado como teclado/D-pad.
  joystick,
}

/// Parametros de calibragem e performance da experiencia VR.
///
/// Tudo que e "ajustavel no campo" mora aqui: e este objeto que e serializado
/// para o WebView na inicializacao da cena e a cada mudanca no menu.
class VrConfig {
  const VrConfig({
    this.deviceOrientation = VrDeviceOrientation.landscapeLeft,
    this.locomotionMode = LocomotionMode.gaze,
    this.stereoEnabled = true,
    this.lensDistortionEnabled = true,
    this.interpupillaryDistance = 0.064,
    this.fieldOfView = 75.0,
    this.distortionK1 = 0.22,
    this.distortionK2 = 0.24,
    this.lensCenterOffset = 0.0,
    this.maxPixelRatio = 1.5,
    this.antialias = false,
    this.targetFps = 60,
    this.walkSpeed = 2.6,
    this.runSpeed = 5.0,
    this.acceleration = 9.0,
    this.damping = 11.0,
    this.eyeHeight = 1.68,
    this.worldRadius = 90.0,
    this.gazeWalkPitchThreshold = -22.0,
    this.headBobAmplitude = 0.022,
    this.headBobFrequency = 1.9,
    this.gyroFilterKp = 1.6,
    this.gyroFilterKi = 0.02,
    this.showDebugHud = false,
  });

  // ---------------------------------------------------------------------
  // Optica / estereoscopia
  // ---------------------------------------------------------------------

  /// Como o aparelho esta encaixado no visor.
  final VrDeviceOrientation deviceOrientation;

  /// Esquema de locomocao ativo.
  final LocomotionMode locomotionMode;

  /// `false` renderiza mono (util para testar sem o visor).
  final bool stereoEnabled;

  /// Pre-distorcao de barril para cancelar a pincushion das lentes Cardboard.
  final bool lensDistortionEnabled;

  /// Distancia interpupilar em metros (media adulta: 0.063 m).
  final double interpupillaryDistance;

  /// FOV vertical de cada olho, em graus.
  final double fieldOfView;

  /// Coeficientes radiais da pre-distorcao (`r' = r * (1 + k1*r^2 + k2*r^4)`).
  final double distortionK1;
  final double distortionK2;

  /// Deslocamento horizontal do centro da lente, em fracao da meia-tela.
  /// Positivo empurra o centro optico para fora (em direcao as bordas).
  final double lensCenterOffset;

  // ---------------------------------------------------------------------
  // Performance
  // ---------------------------------------------------------------------

  /// Teto do `devicePixelRatio`. Telas 1440p com DPR 3.0 derrubam o FPS;
  /// 1.5 e o melhor compromisso nitidez/performance em VR mobile.
  final double maxPixelRatio;

  /// MSAA do contexto WebGL. Desligado por padrao (custo alto em tile GPUs).
  final bool antialias;

  /// FPS alvo do loop de fisica em Dart.
  final int targetFps;

  // ---------------------------------------------------------------------
  // Locomocao / fisica
  // ---------------------------------------------------------------------

  final double walkSpeed;
  final double runSpeed;

  /// Aceleracao (m/s^2) aplicada em direcao a velocidade desejada.
  final double acceleration;

  /// Amortecimento exponencial quando nao ha input (1/s).
  final double damping;

  /// Altura dos olhos acima do chao, em metros.
  final double eyeHeight;

  /// Raio do mapa jogavel, em metros. Fora dele o movimento e bloqueado.
  final double worldRadius;

  /// Pitch (graus) abaixo do qual o "gaze walking" e acionado.
  /// Negativo = olhando para baixo.
  final double gazeWalkPitchThreshold;

  /// Amplitude/frequencia do head bob. Amplitude 0 desliga (menos enjoo).
  final double headBobAmplitude;
  final double headBobFrequency;

  // ---------------------------------------------------------------------
  // Filtro de orientacao
  // ---------------------------------------------------------------------

  /// Ganhos proporcional/integral do filtro complementar (Mahony).
  /// Kp alto = corrige a deriva rapido porem transfere ruido do acelerometro.
  final double gyroFilterKp;
  final double gyroFilterKi;

  /// Exibe o HUD de diagnostico (FPS, pitch/yaw, posicao) nos dois olhos.
  final bool showDebugHud;

  /// Limiar de gaze em radianos.
  double get gazeWalkPitchThresholdRad => gazeWalkPitchThreshold * math.pi / 180.0;

  VrConfig copyWith({
    VrDeviceOrientation? deviceOrientation,
    LocomotionMode? locomotionMode,
    bool? stereoEnabled,
    bool? lensDistortionEnabled,
    double? interpupillaryDistance,
    double? fieldOfView,
    double? distortionK1,
    double? distortionK2,
    double? lensCenterOffset,
    double? maxPixelRatio,
    bool? antialias,
    int? targetFps,
    double? walkSpeed,
    double? runSpeed,
    double? acceleration,
    double? damping,
    double? eyeHeight,
    double? worldRadius,
    double? gazeWalkPitchThreshold,
    double? headBobAmplitude,
    double? headBobFrequency,
    double? gyroFilterKp,
    double? gyroFilterKi,
    bool? showDebugHud,
  }) {
    return VrConfig(
      deviceOrientation: deviceOrientation ?? this.deviceOrientation,
      locomotionMode: locomotionMode ?? this.locomotionMode,
      stereoEnabled: stereoEnabled ?? this.stereoEnabled,
      lensDistortionEnabled: lensDistortionEnabled ?? this.lensDistortionEnabled,
      interpupillaryDistance: interpupillaryDistance ?? this.interpupillaryDistance,
      fieldOfView: fieldOfView ?? this.fieldOfView,
      distortionK1: distortionK1 ?? this.distortionK1,
      distortionK2: distortionK2 ?? this.distortionK2,
      lensCenterOffset: lensCenterOffset ?? this.lensCenterOffset,
      maxPixelRatio: maxPixelRatio ?? this.maxPixelRatio,
      antialias: antialias ?? this.antialias,
      targetFps: targetFps ?? this.targetFps,
      walkSpeed: walkSpeed ?? this.walkSpeed,
      runSpeed: runSpeed ?? this.runSpeed,
      acceleration: acceleration ?? this.acceleration,
      damping: damping ?? this.damping,
      eyeHeight: eyeHeight ?? this.eyeHeight,
      worldRadius: worldRadius ?? this.worldRadius,
      gazeWalkPitchThreshold: gazeWalkPitchThreshold ?? this.gazeWalkPitchThreshold,
      headBobAmplitude: headBobAmplitude ?? this.headBobAmplitude,
      headBobFrequency: headBobFrequency ?? this.headBobFrequency,
      gyroFilterKp: gyroFilterKp ?? this.gyroFilterKp,
      gyroFilterKi: gyroFilterKi ?? this.gyroFilterKi,
      showDebugHud: showDebugHud ?? this.showDebugHud,
    );
  }

  /// Payload enviado ao WebView (`VRB.configure`).
  Map<String, dynamic> toRendererJson() => <String, dynamic>{
        'stereo': stereoEnabled,
        'distortion': lensDistortionEnabled,
        'ipd': interpupillaryDistance,
        'fov': fieldOfView,
        'k1': distortionK1,
        'k2': distortionK2,
        'lensCenterOffset': lensCenterOffset,
        'maxPixelRatio': maxPixelRatio,
        'antialias': antialias,
        'worldRadius': worldRadius,
        'eyeHeight': eyeHeight,
      };
}
