import 'package:shared_preferences/shared_preferences.dart';

import 'vr_config.dart';

/// Persistencia das preferencias de calibragem.
///
/// Guardamos apenas o que e realmente pessoal (optica, conforto, modo de
/// locomocao). Ajustes de cena continuam vindo do codigo.
class VrPreferences {
  static const String _kStereo = 'vr.stereo';
  static const String _kDistortion = 'vr.distortion';
  static const String _kIpd = 'vr.ipd';
  static const String _kFov = 'vr.fov';
  static const String _kK1 = 'vr.k1';
  static const String _kK2 = 'vr.k2';
  static const String _kOrientation = 'vr.orientation';
  static const String _kLocomotion = 'vr.locomotion';
  static const String _kWalkSpeed = 'vr.walkSpeed';
  static const String _kHeadBob = 'vr.headBob';
  static const String _kPixelRatio = 'vr.pixelRatio';
  static const String _kDebugHud = 'vr.debugHud';

  /// Le a configuracao salva, caindo nos padroes de [VrConfig] quando ausente.
  static Future<VrConfig> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    const VrConfig d = VrConfig();
    return VrConfig(
      stereoEnabled: p.getBool(_kStereo) ?? d.stereoEnabled,
      lensDistortionEnabled: p.getBool(_kDistortion) ?? d.lensDistortionEnabled,
      interpupillaryDistance:
          p.getDouble(_kIpd) ?? d.interpupillaryDistance,
      fieldOfView: p.getDouble(_kFov) ?? d.fieldOfView,
      distortionK1: p.getDouble(_kK1) ?? d.distortionK1,
      distortionK2: p.getDouble(_kK2) ?? d.distortionK2,
      deviceOrientation: _enumAt(
        VrDeviceOrientation.values,
        p.getInt(_kOrientation),
        d.deviceOrientation,
      ),
      locomotionMode: _enumAt(
        LocomotionMode.values,
        p.getInt(_kLocomotion),
        d.locomotionMode,
      ),
      walkSpeed: p.getDouble(_kWalkSpeed) ?? d.walkSpeed,
      headBobAmplitude: p.getDouble(_kHeadBob) ?? d.headBobAmplitude,
      maxPixelRatio: p.getDouble(_kPixelRatio) ?? d.maxPixelRatio,
      showDebugHud: p.getBool(_kDebugHud) ?? d.showDebugHud,
    );
  }

  /// Le um enum pelo indice salvo, tolerando valores fora da faixa (o que
  /// acontece quando um enum ganha ou perde membros entre versoes do app).
  static T _enumAt<T>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  static Future<void> save(VrConfig c) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Future.wait<void>(<Future<void>>[
      p.setBool(_kStereo, c.stereoEnabled),
      p.setBool(_kDistortion, c.lensDistortionEnabled),
      p.setDouble(_kIpd, c.interpupillaryDistance),
      p.setDouble(_kFov, c.fieldOfView),
      p.setDouble(_kK1, c.distortionK1),
      p.setDouble(_kK2, c.distortionK2),
      p.setInt(_kOrientation, c.deviceOrientation.index),
      p.setInt(_kLocomotion, c.locomotionMode.index),
      p.setDouble(_kWalkSpeed, c.walkSpeed),
      p.setDouble(_kHeadBob, c.headBobAmplitude),
      p.setDouble(_kPixelRatio, c.maxPixelRatio),
      p.setBool(_kDebugHud, c.showDebugHud),
    ]);
  }
}
