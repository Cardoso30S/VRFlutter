import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../core/vr_config.dart';

/// Conversao entre o referencial dos sensores e o referencial da camera 3D.
///
/// ## Referencial do aparelho (Android e iOS normalizado pelo sensors_plus)
///
/// Com o aparelho em RETRATO natural, olhando para a tela:
///   * `+X` -> para a direita da tela
///   * `+Y` -> para o topo da tela
///   * `+Z` -> sai da tela em direcao ao usuario
///
/// O acelerometro mede *forca especifica*: em repouso ele le `+9.81 m/s^2` no
/// eixo que estiver apontando para CIMA.
///
/// ## Referencial do mundo (Three.js / WebGL)
///
///   * `+Y` -> cima
///   * `-Z` -> frente da camera
///   * `+X` -> direita da camera
///
/// ## Alinhamento
///
/// O filtro em [HeadTracker] estima `qBody`, a rotacao que leva o referencial
/// do CORPO do aparelho para o referencial do MUNDO (Y para cima). Falta
/// compor com a rotacao fixa que leva o referencial da CAMERA para o do CORPO,
/// que depende de como o aparelho foi encaixado no visor:
///
/// `landscapeLeft` (topo do aparelho a esquerda do usuario):
///   * direita da camera = `-Y` do aparelho
///   * cima da camera    = `+X` do aparelho
///   * tras da camera    = `+Z` do aparelho
///   Isso e exatamente uma rotacao de `-90 graus` em torno de `Z` do aparelho.
///
/// `landscapeRight` e a rotacao oposta, `+90 graus` em torno de `Z`.
///
/// Logo: `qCamera = qBody * qAlign`.
class OrientationMapping {
  OrientationMapping(this.orientation)
      : alignment = _alignmentFor(orientation);

  final VrDeviceOrientation orientation;

  /// Rotacao camera -> corpo do aparelho.
  final Quaternion alignment;

  static Quaternion _alignmentFor(VrDeviceOrientation orientation) {
    final double angle = switch (orientation) {
      VrDeviceOrientation.landscapeLeft => -math.pi / 2,
      VrDeviceOrientation.landscapeRight => math.pi / 2,
    };
    return Quaternion.axisAngle(Vector3(0, 0, 1), angle)..normalize();
  }

  /// Compoe a orientacao do corpo com o alinhamento do visor.
  Quaternion toCamera(Quaternion body) => (body * alignment)..normalize();
}

/// Angulos de Euler extraidos de um quaternion de camera (convencao YXZ:
/// yaw em torno de `+Y`, depois pitch em torno de `+X`, depois roll em `+Z`).
///
/// Usamos YXZ porque e a mesma ordem que o Three.js usa para camera e porque
/// evita gimbal lock nas poses uteis (olhar para cima/baixo perto de +-90 graus
/// e raro em VR sentado).
class EulerAngles {
  const EulerAngles(this.yaw, this.pitch, this.roll);

  /// Rotacao em torno de `+Y` (radianos). 0 = olhando para `-Z`.
  final double yaw;

  /// Rotacao em torno de `+X` (radianos). Negativo = olhando para baixo.
  final double pitch;

  /// Rotacao em torno de `+Z` (radianos), inclinacao lateral da cabeca.
  final double roll;

  /// Extrai YXZ a partir da matriz de rotacao do quaternion.
  factory EulerAngles.fromQuaternion(Quaternion q) {
    final Matrix3 m = q.asRotationMatrix();
    // Colunas/linhas em vector_math: m.entry(row, col).
    final double m12 = m.entry(1, 2);
    final double clamped = m12.clamp(-1.0, 1.0);
    final double pitch = math.asin(-clamped);
    late final double yaw;
    late final double roll;
    if (clamped.abs() < 0.9999999) {
      yaw = math.atan2(m.entry(0, 2), m.entry(2, 2));
      roll = math.atan2(m.entry(1, 0), m.entry(1, 1));
    } else {
      // Perto do polo: colapsa roll no yaw.
      yaw = math.atan2(-m.entry(2, 0), m.entry(0, 0));
      roll = 0.0;
    }
    return EulerAngles(yaw, pitch, roll);
  }

  double get yawDegrees => yaw * 180.0 / math.pi;
  double get pitchDegrees => pitch * 180.0 / math.pi;
  double get rollDegrees => roll * 180.0 / math.pi;
}
