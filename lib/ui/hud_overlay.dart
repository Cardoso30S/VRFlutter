import 'package:flutter/material.dart';

/// Duplica um widget nas duas metades da tela, para que o conteudo apareca
/// centralizado em cada olho quando o modo estereo esta ativo.
///
/// Cada metade recebe uma copia identica: em VR os dois olhos precisam ver o
/// mesmo HUD, com a mesma posicao relativa a sua propria viewport.
class StereoOverlay extends StatelessWidget {
  const StereoOverlay({
    super.key,
    required this.stereo,
    required this.child,
  });

  final bool stereo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!stereo) return child;
    return Row(
      children: <Widget>[
        Expanded(child: child),
        Expanded(child: child),
      ],
    );
  }
}

/// HUD de diagnostico exibido em cada olho.
class DebugHud extends StatelessWidget {
  const DebugHud({
    super.key,
    required this.lines,
  });

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xAA000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final String line in lines)
                    Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xFF9BE7A0),
                        fontSize: 9,
                        height: 1.35,
                        fontFamily: 'monospace',
                        fontFamilyFallback: <String>['Menlo', 'Roboto Mono'],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela de carregamento / instrucoes, exibida antes da cena ficar pronta.
class BootOverlay extends StatelessWidget {
  const BootOverlay({
    super.key,
    required this.progress,
    required this.message,
    this.error,
    this.onRetry,
  });

  final double progress;
  final String message;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool failed = error != null;
    return ColoredBox(
      color: const Color(0xF20A0D10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                failed ? 'Falha ao iniciar a cena' : 'Preparando o Cretaceo...',
                style: TextStyle(
                  color: failed
                      ? const Color(0xFFFFB4A9)
                      : const Color(0xFFE8E1D4),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  failed ? error! : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9AA3AD),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (!failed)
                SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: const Color(0xFF1E242B),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF6FCF97),
                    ),
                  ),
                )
              else if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Tentar novamente'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
