import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/vr_config.dart';
import '../engine/vr_state.dart';
import '../engine/world_bounds.dart';

/// Estatisticas reportadas pelo renderizador WebGL.
class RendererStats {
  const RendererStats({
    required this.fps,
    required this.drawCalls,
    required this.triangles,
    required this.textures,
    required this.programs,
  });

  final double fps;
  final int drawCalls;
  final int triangles;
  final int textures;
  final int programs;

  static const RendererStats empty = RendererStats(
    fps: 0,
    drawCalls: 0,
    triangles: 0,
    textures: 0,
    programs: 0,
  );

  factory RendererStats.fromMap(Map<dynamic, dynamic> m) => RendererStats(
        fps: (m['fps'] as num?)?.toDouble() ?? 0,
        drawCalls: (m['calls'] as num?)?.toInt() ?? 0,
        triangles: (m['tris'] as num?)?.toInt() ?? 0,
        textures: (m['tex'] as num?)?.toInt() ?? 0,
        programs: (m['prog'] as num?)?.toInt() ?? 0,
      );
}

/// Ponte Dart <-> JavaScript da cena VR.
///
/// ## Divisao de responsabilidades
///
/// * **Dart** e dono dos sensores, da fisica e da UI. Empurra um pacote
///   compacto de estado por frame.
/// * **JavaScript** e dono do WebGL. Roda o proprio `requestAnimationFrame` e
///   **interpola** entre os pacotes recebidos, de modo que a renderizacao
///   nunca fique presa a taxa da ponte (que e assincrona e pode engasgar).
///
/// A ponte usa `evaluateJavascript` com uma unica chamada por frame e
/// aplica backpressure: se a chamada anterior ainda nao retornou, o frame e
/// descartado em vez de enfileirado. Enfileirar acumularia latencia de
/// head-tracking - o pior defeito possivel em VR.
class VrWebBridge {
  VrWebBridge({
    this.onSceneReady,
    this.onColliders,
    this.onStats,
    this.onLog,
    this.onError,
  });

  /// Chamado quando a cena terminou de carregar (modelos incluidos).
  final void Function(Map<String, dynamic> info)? onSceneReady;

  /// Colisores gerados proceduralmente no lado WebGL.
  final void Function(List<CircleCollider> colliders)? onColliders;

  /// Estatisticas periodicas (1 Hz).
  final void Function(RendererStats stats)? onStats;

  /// Logs do JS encaminhados para o Dart (uteis em release).
  final void Function(String message)? onLog;

  /// Erros fatais do renderizador (ex.: WebGL indisponivel).
  final void Function(String message)? onError;

  InAppWebViewController? _controller;
  bool _sceneReady = false;
  bool _inFlight = false;
  int _droppedFrames = 0;

  bool get isReady => _sceneReady;
  int get droppedFrames => _droppedFrames;

  /// Registra os handlers JS. Chame em `onWebViewCreated`.
  void attach(InAppWebViewController controller) {
    _controller = controller;

    controller.addJavaScriptHandler(
      handlerName: 'vrSceneReady',
      callback: (List<dynamic> args) {
        _sceneReady = true;
        final Map<String, dynamic> info = args.isNotEmpty && args.first is Map
            ? Map<String, dynamic>.from(args.first as Map)
            : <String, dynamic>{};
        onSceneReady?.call(info);
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'vrColliders',
      callback: (List<dynamic> args) {
        if (args.isEmpty || args.first is! List) return null;
        final List<dynamic> raw = args.first as List<dynamic>;
        final List<CircleCollider> parsed = <CircleCollider>[];
        // Formato plano [x, z, r, x, z, r, ...] para reduzir o custo de
        // serializacao na ponte.
        for (int i = 0; i + 2 < raw.length; i += 3) {
          parsed.add(CircleCollider(
            (raw[i] as num).toDouble(),
            (raw[i + 1] as num).toDouble(),
            (raw[i + 2] as num).toDouble(),
          ));
        }
        onColliders?.call(parsed);
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'vrStats',
      callback: (List<dynamic> args) {
        if (args.isNotEmpty && args.first is Map) {
          onStats?.call(RendererStats.fromMap(args.first as Map));
        }
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'vrLog',
      callback: (List<dynamic> args) {
        onLog?.call(args.isEmpty ? '' : args.first.toString());
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'vrError',
      callback: (List<dynamic> args) {
        onError?.call(args.isEmpty ? 'erro desconhecido' : args.first.toString());
        return null;
      },
    );
  }

  void detach() {
    _controller = null;
    _sceneReady = false;
    _inFlight = false;
  }

  /// Envia a configuracao de optica/performance para o renderizador.
  Future<void> pushConfig(VrConfig config) async {
    final InAppWebViewController? c = _controller;
    if (c == null) return;
    final String json = jsonEncode(config.toRendererJson());
    await c.evaluateJavascript(source: 'window.VRB && VRB.configure($json);');
  }

  /// Envia o estado do frame. Nao aguarda o retorno em caso de congestao.
  void pushState(VrFrameState state) {
    final InAppWebViewController? c = _controller;
    if (c == null || !_sceneReady || _inFlight) {
      if (_inFlight) _droppedFrames++;
      return;
    }
    _inFlight = true;
    c
        .evaluateJavascript(source: 'VRB.s(${state.toJsArgs()});')
        .whenComplete(() => _inFlight = false)
        .catchError((Object _) => _inFlight = false);
  }

  /// Solicita a recentragem visual (reticulo, bussola) no lado da cena.
  Future<void> notifyRecenter() async {
    await _controller?.evaluateJavascript(
      source: 'window.VRB && VRB.recenter();',
    );
  }

  /// Pausa/retoma o `requestAnimationFrame` da cena (economiza bateria
  /// quando o app vai para segundo plano).
  Future<void> setPaused({required bool paused}) async {
    await _controller?.evaluateJavascript(
      source: 'window.VRB && VRB.setPaused($paused);',
    );
  }
}
