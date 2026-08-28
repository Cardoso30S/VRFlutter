import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../vr_state.dart';

/// Estado compartilhado do joystick virtual.
///
/// Mantido fora do `State` do widget para que o loop de fisica leia o valor
/// sem depender de rebuilds - o joystick atualiza a 60 Hz e um `setState` por
/// evento de arraste custaria caro.
class JoystickController extends ChangeNotifier {
  Offset _origin = Offset.zero;
  Offset _current = Offset.zero;
  bool _active = false;

  /// Raio (em pixels logicos) para deflexao maxima.
  double radius = 80.0;

  bool get isActive => _active;
  Offset get origin => _origin;
  Offset get knob => _current;

  LocomotionInput get value {
    if (!_active) return LocomotionInput.idle;
    final Offset d = _current - _origin;
    final double len = d.distance;
    if (len < 6.0) return LocomotionInput.idle; // zona morta
    final double clamped = math.min(len, radius) / radius;
    final double nx = d.dx / len;
    final double ny = d.dy / len;
    // Eixo Y da tela cresce para baixo; arrastar para cima = andar para frente.
    return LocomotionInput(
      strafe: nx * clamped,
      forward: -ny * clamped,
      running: clamped > 0.92,
    );
  }

  void begin(Offset position) {
    _origin = position;
    _current = position;
    _active = true;
    notifyListeners();
  }

  void update(Offset position) {
    _current = position;
    // Sem notifyListeners aqui: o repaint do overlay e feito pelo Ticker da
    // cena, evitando um rebuild por evento de ponteiro.
  }

  void end() {
    _active = false;
    notifyListeners();
  }
}

/// Overlay que desenha o joystick em UM dos olhos (ou nos dois, quando
/// [stereo] e `true`).
///
/// Em uso real com o visor o joystick nao precisa ser visivel - a area de
/// toque cobre a tela inteira. Ele existe principalmente para testes em modo
/// mono e para o usuario aprender o gesto.
class JoystickOverlay extends StatelessWidget {
  const JoystickOverlay({
    super.key,
    required this.controller,
    required this.stereo,
    this.color = const Color(0x66FFFFFF),
  });

  final JoystickController controller;
  final bool stereo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _JoystickPainter(
            controller: controller,
            stereo: stereo,
            color: color,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.controller,
    required this.stereo,
    required this.color,
  }) : super(repaint: controller);

  final JoystickController controller;
  final bool stereo;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isActive) return;

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color;
    final Paint knob = Paint()..color = color;

    void draw(Offset origin, Offset current) {
      canvas.drawCircle(origin, controller.radius, ring);
      final Offset d = current - origin;
      final double len = d.distance;
      final Offset clamped = len > controller.radius
          ? origin + d * (controller.radius / len)
          : current;
      canvas.drawCircle(clamped, 18.0, knob);
    }

    if (!stereo) {
      draw(controller.origin, controller.knob);
      return;
    }

    // Em estereo, o gesto acontece em coordenadas de tela cheia; projetamos
    // o mesmo desenho no centro de cada metade.
    final double half = size.width / 2;
    final Offset o = Offset(controller.origin.dx % half, controller.origin.dy);
    final Offset k = o + (controller.knob - controller.origin);
    draw(o, k);
    draw(o + Offset(half, 0), k + Offset(half, 0));
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) => true;
}
