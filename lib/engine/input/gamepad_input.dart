import 'package:flutter/services.dart';

import '../vr_state.dart';

/// Adaptador para controles Bluetooth (Opcao B).
///
/// A maioria dos gamepads/clickers Bluetooth de mercado se anuncia como
/// teclado HID: D-pad vira setas, o botao principal vira Enter/Espaco. Por
/// isso lemos o teclado de hardware em vez de depender de um plugin de
/// gamepad, o que funciona tanto no Android quanto no iOS sem codigo nativo.
///
/// Tambem cobre teclado fisico no emulador/desktop (WASD), util no
/// desenvolvimento.
class GamepadInput {
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  // Precisam ser `final` e nao `const`: no Dart 3 uma colecao constante exige
  // elementos com igualdade primitiva, e `LogicalKeyboardKey` sobrescreve o
  // `==`. Como sao `static`, continuam sendo criadas uma unica vez.
  //
  // Nao existem `gameButtonUp/Down/Left/Right` no Flutter - e nao fazem falta:
  // o D-pad dos gamepads Bluetooth chega ao Flutter como as teclas de seta.
  static final Set<LogicalKeyboardKey> _forward = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyW,
  };
  static final Set<LogicalKeyboardKey> _backward = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyS,
  };
  static final Set<LogicalKeyboardKey> _left = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyA,
  };
  static final Set<LogicalKeyboardKey> _right = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyD,
  };
  static final Set<LogicalKeyboardKey> _run = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.gameButtonB,
  };

  /// Teclas que disparam o "gatilho" (equivalente ao botao do Cardboard).
  static final Set<LogicalKeyboardKey> triggerKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.gameButtonStart,
  };

  /// Processa um evento de teclado. Devolve `true` se o evento foi consumido.
  bool handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      return _pressed.add(event.logicalKey);
    }
    if (event is KeyUpEvent) {
      return _pressed.remove(event.logicalKey);
    }
    return false;
  }

  bool get triggerPressed => _pressed.any(triggerKeys.contains);

  bool get hasInput => _pressed.isNotEmpty;

  LocomotionInput get value {
    double forward = 0.0;
    double strafe = 0.0;
    if (_pressed.any(_forward.contains)) forward += 1.0;
    if (_pressed.any(_backward.contains)) forward -= 1.0;
    if (_pressed.any(_right.contains)) strafe += 1.0;
    if (_pressed.any(_left.contains)) strafe -= 1.0;
    if (forward == 0.0 && strafe == 0.0) return LocomotionInput.idle;
    return LocomotionInput(
      forward: forward,
      strafe: strafe,
      running: _pressed.any(_run.contains),
    ).clampedToUnitCircle();
  }

  void clear() => _pressed.clear();
}
