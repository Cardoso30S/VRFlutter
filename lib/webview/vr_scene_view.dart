import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'vr_web_bridge.dart';

/// Porta HTTP do servidor local que serve os assets da cena.
///
/// **Por que um servidor local e nao `file://`?** Modulos ES (`import`) sao
/// bloqueados pela politica de CORS quando carregados de `file://` no
/// Chromium/WebKit. Servir os mesmos assets do bundle Flutter por
/// `http://127.0.0.1` resolve isso e ainda habilita `fetch()` do manifesto
/// de modelos.
const int kVrServerPort = 8099;

/// Caminho do `index.html` dentro do bundle (o servidor usa a raiz dos assets).
const String kVrIndexPath = '/assets/web/index.html';

/// WebView que hospeda a cena Three.js.
///
/// Encapsula ciclo de vida do [InAppLocalhostServer], as `InAppWebViewSettings`
/// otimizadas para VR (sem scroll, sem zoom, sem overscroll, aceleracao de
/// hardware) e a ligacao com o [VrWebBridge].
class VrSceneView extends StatefulWidget {
  const VrSceneView({
    super.key,
    required this.bridge,
    this.onProgress,
  });

  final VrWebBridge bridge;

  /// 0..1 durante o carregamento da pagina.
  final ValueChanged<double>? onProgress;

  @override
  State<VrSceneView> createState() => _VrSceneViewState();
}

class _VrSceneViewState extends State<VrSceneView> {
  static final InAppLocalhostServer _server =
      InAppLocalhostServer(port: kVrServerPort, documentRoot: './');

  Future<void>? _serverBoot;

  @override
  void initState() {
    super.initState();
    _serverBoot = _startServer();
  }

  Future<void> _startServer() async {
    if (!_server.isRunning()) {
      await _server.start();
    }
  }

  @override
  void dispose() {
    widget.bridge.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _serverBoot,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Color(0xFF06080C));
        }
        if (snapshot.hasError) {
          return _FatalError(
            message: 'Falha ao iniciar o servidor local:\n${snapshot.error}',
          );
        }
        return InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('http://127.0.0.1:$kVrServerPort$kVrIndexPath'),
          ),
          initialSettings: InAppWebViewSettings(
            // --- Performance ---
            hardwareAcceleration: true,
            useHybridComposition: true,
            transparentBackground: false,
            // --- Comportamento de VR: nada de scroll/zoom/selecao ---
            disableVerticalScroll: true,
            disableHorizontalScroll: true,
            supportZoom: false,
            builtInZoomControls: false,
            displayZoomControls: false,
            disableContextMenu: true,
            disableLongPressContextMenuOnLinks: true,
            overScrollMode: OverScrollMode.NEVER,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            // O canvas WebGL deve ocupar exatamente o viewport fisico.
            useWideViewPort: false,
            loadWithOverviewMode: false,
            // --- Midia/JS ---
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            // --- iOS ---
            allowsBackForwardNavigationGestures: false,
            disallowOverScroll: true,
            // Cleartext apenas para o servidor local (ver network_security_config).
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            cacheEnabled: true,
          ),
          onWebViewCreated: widget.bridge.attach,
          onProgressChanged: (_, int progress) =>
              widget.onProgress?.call(progress / 100.0),
          onConsoleMessage: (_, ConsoleMessage msg) {
            if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
              debugPrint('[VR/JS] ${msg.message}');
            }
          },
          onReceivedError: (_, WebResourceRequest req, WebResourceError err) {
            debugPrint('[VR/WebView] ${req.url} -> ${err.description}');
          },
          // A cena nao navega para lugar nenhum: bloqueia qualquer tentativa.
          shouldOverrideUrlLoading: (_, NavigationAction action) async {
            final String? url = action.request.url?.toString();
            if (url != null &&
                url.startsWith('http://127.0.0.1:$kVrServerPort')) {
              return NavigationActionPolicy.ALLOW;
            }
            return NavigationActionPolicy.CANCEL;
          },
        );
      },
    );
  }
}

class _FatalError extends StatelessWidget {
  const _FatalError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1A0A0A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFB4A9), fontSize: 13),
          ),
        ),
      ),
    );
  }
}
