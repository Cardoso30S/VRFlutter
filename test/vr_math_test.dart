import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:vr_dino_cardboard/core/vr_config.dart';
import 'package:vr_dino_cardboard/engine/vr_state.dart';
import 'package:vr_dino_cardboard/engine/world_bounds.dart';
import 'package:vr_dino_cardboard/sensors/orientation_mapping.dart';

void main() {
  group('OrientationMapping', () {
    test('landscapeLeft em repouso resulta em camera identidade', () {
      // Com o aparelho em paisagem (topo a esquerda) e a tela na vertical,
      // o acelerometro le +g no eixo +X do aparelho. O filtro converge para
      // um quaternion que leva +X do corpo ate +Y do mundo, ou seja, uma
      // rotacao de +90 graus em torno de Z.
      final Quaternion body =
          Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2)..normalize();

      final OrientationMapping mapping =
          OrientationMapping(VrDeviceOrientation.landscapeLeft);
      final Quaternion camera = mapping.toCamera(body);

      // A camera deve olhar para -Z do mundo com +Y para cima.
      final Vector3 forward = camera.rotated(Vector3(0, 0, -1));
      final Vector3 up = camera.rotated(Vector3(0, 1, 0));

      expect(forward.x, closeTo(0, 1e-9));
      expect(forward.y, closeTo(0, 1e-9));
      expect(forward.z, closeTo(-1, 1e-9));
      expect(up.y, closeTo(1, 1e-9));
    });

    test('landscapeRight e o inverso de landscapeLeft', () {
      final Quaternion body = Quaternion.identity();
      final Quaternion left =
          OrientationMapping(VrDeviceOrientation.landscapeLeft).toCamera(body);
      final Quaternion right =
          OrientationMapping(VrDeviceOrientation.landscapeRight).toCamera(body);
      // 180 graus de diferenca em torno de Z entre as duas montagens.
      final Quaternion delta = (left.inverted() * right)..normalize();
      expect(delta.radians.abs(), closeTo(math.pi, 1e-6));
    });
  });

  group('EulerAngles', () {
    test('quaternion identidade nao tem rotacao', () {
      final EulerAngles e = EulerAngles.fromQuaternion(Quaternion.identity());
      expect(e.yaw, closeTo(0, 1e-9));
      expect(e.pitch, closeTo(0, 1e-9));
      expect(e.roll, closeTo(0, 1e-9));
    });

    test('olhar para baixo produz pitch negativo', () {
      // Rotacao de -30 graus em torno de +X = nariz para baixo.
      final Quaternion q =
          Quaternion.axisAngle(Vector3(1, 0, 0), -30 * math.pi / 180)
            ..normalize();
      final EulerAngles e = EulerAngles.fromQuaternion(q);
      expect(e.pitchDegrees, closeTo(-30, 1e-6));
      expect(e.yawDegrees, closeTo(0, 1e-6));
    });

    test('yaw de 90 graus gira a frente para -X', () {
      final Quaternion q =
          Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2)..normalize();
      final EulerAngles e = EulerAngles.fromQuaternion(q);
      expect(e.yawDegrees, closeTo(90, 1e-6));

      final Vector3 forward = q.rotated(Vector3(0, 0, -1));
      expect(forward.x, closeTo(-1, 1e-9));
      expect(forward.z, closeTo(0, 1e-9));
    });
  });

  group('WorldBounds', () {
    test('mantem o jogador dentro do raio do mapa', () {
      final WorldBounds b = WorldBounds(radius: 50, playerRadius: 0.5);
      final List<double> out = <double>[0, 0];
      b.resolve(100, 0, out);
      expect(math.sqrt(out[0] * out[0] + out[1] * out[1]),
          closeTo(49.5, 1e-6));
    });

    test('empurra o jogador para fora de um obstaculo', () {
      final WorldBounds b = WorldBounds(radius: 50, playerRadius: 0.5);
      b.setColliders(<CircleCollider>[const CircleCollider(10, 0, 2)]);
      final List<double> out = <double>[0, 0];
      // Entrando pelo lado esquerdo do obstaculo.
      b.resolve(9.0, 0, out);
      final double dist = math.sqrt(
        (out[0] - 10) * (out[0] - 10) + out[1] * out[1],
      );
      expect(dist, closeTo(2.5, 1e-6));
      expect(out[0], lessThan(10));
    });

    test('nao altera posicoes livres', () {
      final WorldBounds b = WorldBounds(radius: 50, playerRadius: 0.5);
      b.setColliders(<CircleCollider>[const CircleCollider(10, 0, 2)]);
      final List<double> out = <double>[0, 0];
      b.resolve(1, 1, out);
      expect(out[0], closeTo(1, 1e-9));
      expect(out[1], closeTo(1, 1e-9));
    });
  });

  group('LocomotionInput', () {
    test('normaliza a diagonal para o circulo unitario', () {
      const LocomotionInput i = LocomotionInput(strafe: 1, forward: 1);
      final LocomotionInput c = i.clampedToUnitCircle();
      final double len = math.sqrt(c.strafe * c.strafe + c.forward * c.forward);
      expect(len, closeTo(1.0, 1e-9));
    });

    test('preserva entradas dentro do circulo', () {
      const LocomotionInput i = LocomotionInput(strafe: 0.3, forward: -0.4);
      final LocomotionInput c = i.clampedToUnitCircle();
      expect(c.strafe, 0.3);
      expect(c.forward, -0.4);
    });
  });

  group('VrFrameState', () {
    test('serializa em argumentos posicionais compactos', () {
      final VrFrameState s = VrFrameState(
        position: Vector3(1, 2, 3),
        orientation: Quaternion.identity(),
        speed: 1.5,
        moving: true,
        headBob: 0,
      );
      final List<String> parts = s.toJsArgs().split(',');
      expect(parts.length, 9);
      expect(double.parse(parts[0]), closeTo(1, 1e-4));
      expect(parts.last, '1');
    });
  });
}
