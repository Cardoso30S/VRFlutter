import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/vr_config.dart';
import '../core/vr_preferences.dart';
import '../engine/input/gamepad_input.dart';
import '../engine/input/virtual_joystick.dart';
import '../engine/locomotion_controller.dart';
import '../engine/vr_state.dart';
import '../engine/world_bounds.dart';
import '../sensors/head_tracker.dart';
import '../sensors/orientation_mapping.dart';
import '../webview/vr_scene_view.dart';
import '../webview/vr_web_bridge.dart';
import 'hud_overlay.dart';
import 'settings_sheet.dart';

/// Tela principal da experiencia VR.
///
/// Orquestra os quatro subsistemas:
///
/// 1. [HeadTracker]        - sensores -> orientacao da camera
/// 2. [LocomotionController] - input + orientacao -> posicao no mundo
/// 3. [VrWebBridge]        - estado -> renderizador WebGL
/// 4. Overlays Flutter     - joystick, HUD, menu de calibragem
///
/// O unico `Ticker` do app dirige a fisica e o envio de estado; nenhum
/// `setState` roda por frame (o HUD usa [ValueNotifier] a 4 Hz).
class VrScreen extends StatefulWidget {
  const VrScreen({super.key});

  @override
  State<VrScreen> createState() => _VrScreenState();
}

class _VrScreenState extends State<VrScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VrConfig _config = const VrConfig();

  late final HeadTracker _head = HeadTracker(config: _config);
  late final LocomotionController _locomotion =
      LocomotionController(config: _config, headTracker: _head);
  late final VrWebBridge _bridge;
  final JoystickController _joystick = JoystickController();
  final GamepadInput _gamepad = GamepadInput();
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'vr-gamepad');

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  final ValueNotifier<List<String>> _hudLines =
      ValueNotifier<List<String>>(const <String>[]);
  final ValueNotifier<bool> _sceneReady = ValueNotifier<bool>(false);

  RendererStats _stats = RendererStats.empty;
  final ValueNotifier<double> _loadProgress = ValueNotifier<double>(0);
  String? _fatalError;

  int _lastTapMs = 0;
  int _hudCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bridge = VrWebBridge(
      onSceneReady: _onSceneReady,
      onColliders: (List<CircleCollider> colliders) =>
          _locomotion.bounds.setColliders(colliders),
      onStats: (RendererStats s) => _stats = s,
      onLog: (String m) => debugPrint('[VR/scene] $m'),
      onError: (String m) => setState(() => _fatalError = m),
    );

    _enterImmersiveMode();
    _head.start();

    _ticker = createTicker(_onTick)..start();

    unawaited(_restorePreferences());
  }

  Future<void> _restorePreferences() async {
    final VrConfig saved = await VrPreferences.load();
    if (!mounted) return;
    _applyConfig(saved, persist: false);
  }

  Future<void> _enterImmersiveMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await WakelockPlus.enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    unawaited(_head.stop());
    _keyboardFocus.dispose();
    _joystick.dispose();
    _loadProgress.dispose();
    _hudLines.dispose();
    _sceneReady.dispose();
    unawaited(WakelockPlus.disable());
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool active = state == AppLifecycleState.resumed;
    if (active) {
      _head.start();
      if (!(_ticker?.isTicking ?? false)) _ticker?.start();
    } else {
      _ticker?.stop();
      unawaited(_head.stop());
      _gamepad.clear();
    }
    unawaited(_bridge.setPaused(paused: !active));
  }

  // -------------------------------------------------------------------
  // Loop principal
  // -------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    // 1) Coleta de input conforme o modo ativo.
    if (_config.locomotionMode == LocomotionMode.joystick) {
      final LocomotionInput pad = _gamepad.value;
      _locomotion.input = pad.isActive ? pad : _joystick.value;
    } else {
      // No modo gaze o gamepad ainda pode dar strafe/re, se houver.
      _locomotion.input = _gamepad.value;
    }
    _locomotion.triggerHeld = _joystick.isActive || _gamepad.triggerPressed;

    // 2) Passo de fisica com timestep fixo interno.
    final VrFrameState state = _locomotion.step(dt);

    // 3) Envio para o renderizador (com backpressure).
    _bridge.pushState(state);

    // 4) HUD a ~4 Hz.
    if (_config.showDebugHud && (++_hudCounter % 15 == 0)) {
      _hudLines.value = _buildHudLines(state);
    }
  }

  List<String> _buildHudLines(VrFrameState state) {
    final EulerAngles e = EulerAngles.fromQuaternion(state.orientation);
    return <String>[
      'FPS ${_stats.fps.toStringAsFixed(0)}  draw ${_stats.drawCalls}  '
          'tris ${(_stats.triangles / 1000).toStringAsFixed(1)}k',
      'yaw ${e.yawDegrees.toStringAsFixed(0)}  '
          'pitch ${e.pitchDegrees.toStringAsFixed(0)}  '
          'roll ${e.rollDegrees.toStringAsFixed(0)}',
      'pos ${state.position.x.toStringAsFixed(1)}, '
          '${state.position.z.toStringAsFixed(1)}  '
          'v ${state.speed.toStringAsFixed(2)} m/s',
      'gyro ${_head.gyroscopeAvailable ? "ok" : "AUSENTE"}  '
          'colisores ${_locomotion.bounds.colliderCount}  '
          'drop ${_bridge.droppedFrames}',
    ];
  }

  void _onSceneReady(Map<String, dynamic> info) {
    _sceneReady.value = true;
    unawaited(_bridge.pushConfig(_config));
    debugPrint('[VR] cena pronta: $info');
  }

  // -------------------------------------------------------------------
  // Configuracao
  // -------------------------------------------------------------------

  void _applyConfig(VrConfig next, {bool persist = true}) {
    setState(() => _config = next);
    _head.updateConfig(next);
    _locomotion.updateConfig(next);
    unawaited(_bridge.pushConfig(next));
    if (persist) unawaited(VrPreferences.save(next));
  }

  void _recenter() {
    _head.recenter();
    unawaited(_bridge.notifyRecenter());
    HapticFeedback.mediumImpact();
  }

  Future<void> _openSettings() async {
    _ticker?.stop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11161B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => SettingsSheet(
        config: _config,
        onChanged: _applyConfig,
        onRecenter: _recenter,
        onRespawn: () => _locomotion.teleport(0, 6),
      ),
    );
    if (!mounted) return;
    _lastTick = Duration.zero;
    _ticker?.start();
  }

  // -------------------------------------------------------------------
  // Entrada de ponteiro
  // -------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTapMs < 320) {
      _recenter();
      _lastTapMs = 0;
      return;
    }
    _lastTapMs = now;
    _joystick.begin(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) =>
      _joystick.update(event.localPosition);

  void _onPointerUp(PointerUpEvent event) => _joystick.end();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    return _gamepad.handleKeyEvent(event)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 1) Cena WebGL.
          VrSceneView(
            bridge: _bridge,
            onProgress: (double p) => _loadProgress.value = p,
          ),

          // 2) Captura de toque em tela cheia (fica ACIMA do WebView para que
          //    o canvas nunca receba gestos de scroll/zoom).
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) => _joystick.end(),
            child: const SizedBox.expand(),
          ),

          // 3) Joystick virtual (somente no modo joystick).
          if (_config.locomotionMode == LocomotionMode.joystick)
            JoystickOverlay(
              controller: _joystick,
              stereo: _config.stereoEnabled,
            ),

          // 4) HUD de diagnostico duplicado nos dois olhos.
          if (_config.showDebugHud)
            ValueListenableBuilder<List<String>>(
              valueListenable: _hudLines,
              builder: (_, List<String> lines, __) => StereoOverlay(
                stereo: _config.stereoEnabled,
                child: DebugHud(lines: lines),
              ),
            ),

          // 5) Overlay de boot/erro.
          ValueListenableBuilder<bool>(
            valueListenable: _sceneReady,
            builder: (_, bool ready, __) {
              if (ready && _fatalError == null) {
                return const SizedBox.shrink();
              }
              return ValueListenableBuilder<double>(
                valueListenable: _loadProgress,
                builder: (_, double progress, __) => BootOverlay(
                  progress: progress,
                  message: progress < 0.99
                      ? 'Carregando o renderizador WebGL...'
                      : 'Montando o cenario e os dinossauros...',
                  error: _fatalError,
                  onRetry: () => setState(() => _fatalError = null),
                ),
              );
            },
          ),

          // 6) Acesso ao menu (canto superior esquerdo, fora do campo util
          //    das lentes).
          Positioned(
            left: 4,
            top: 4,
            child: Opacity(
              opacity: 0.35,
              child: IconButton(
                iconSize: 20,
                icon: const Icon(Icons.tune, color: Colors.white),
                tooltip: 'Calibragem',
                onPressed: _openSettings,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
