import 'package:flutter/material.dart';

import '../core/vr_config.dart';

/// Painel de calibragem exibido em modo 2D (fora do visor).
///
/// Todos os parametros aqui afetam conforto: IPD errada causa fadiga ocular,
/// distorcao errada deforma as bordas, velocidade alta causa enjoo.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.config,
    required this.onChanged,
    required this.onRecenter,
    required this.onRespawn,
  });

  final VrConfig config;
  final ValueChanged<VrConfig> onChanged;
  final VoidCallback onRecenter;
  final VoidCallback onRespawn;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late VrConfig _config = widget.config;

  void _apply(VrConfig next) {
    setState(() => _config = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A424B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const _SectionTitle('Optica'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Estereoscopia (split-screen)'),
              subtitle: const Text('Desligue para testar sem o visor'),
              value: _config.stereoEnabled,
              onChanged: (bool v) => _apply(_config.copyWith(stereoEnabled: v)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Correcao de distorcao das lentes'),
              subtitle: const Text('Pre-distorcao de barril (Cardboard)'),
              value: _config.lensDistortionEnabled,
              onChanged: (bool v) =>
                  _apply(_config.copyWith(lensDistortionEnabled: v)),
            ),
            _SliderRow(
              label: 'Distancia interpupilar (IPD)',
              value: _config.interpupillaryDistance * 1000,
              min: 52,
              max: 76,
              unit: 'mm',
              onChanged: (double v) =>
                  _apply(_config.copyWith(interpupillaryDistance: v / 1000)),
            ),
            _SliderRow(
              label: 'Campo de visao',
              value: _config.fieldOfView,
              min: 55,
              max: 100,
              unit: 'graus',
              onChanged: (double v) =>
                  _apply(_config.copyWith(fieldOfView: v)),
            ),
            _SliderRow(
              label: 'Distorcao k1',
              value: _config.distortionK1,
              min: 0.0,
              max: 0.5,
              fractionDigits: 2,
              onChanged: (double v) =>
                  _apply(_config.copyWith(distortionK1: v)),
            ),
            _SliderRow(
              label: 'Distorcao k2',
              value: _config.distortionK2,
              min: 0.0,
              max: 0.6,
              fractionDigits: 2,
              onChanged: (double v) =>
                  _apply(_config.copyWith(distortionK2: v)),
            ),
            const SizedBox(height: 8),
            const _SectionTitle('Encaixe do aparelho no visor'),
            SegmentedButton<VrDeviceOrientation>(
              segments: const <ButtonSegment<VrDeviceOrientation>>[
                ButtonSegment<VrDeviceOrientation>(
                  value: VrDeviceOrientation.landscapeLeft,
                  label: Text('Topo a esquerda'),
                ),
                ButtonSegment<VrDeviceOrientation>(
                  value: VrDeviceOrientation.landscapeRight,
                  label: Text('Topo a direita'),
                ),
              ],
              selected: <VrDeviceOrientation>{_config.deviceOrientation},
              onSelectionChanged: (Set<VrDeviceOrientation> s) =>
                  _apply(_config.copyWith(deviceOrientation: s.first)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Se a imagem aparecer de cabeca para baixo ou o giro responder '
              'invertido, troque esta opcao.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A939C)),
            ),
            const SizedBox(height: 16),
            const _SectionTitle('Locomocao'),
            SegmentedButton<LocomotionMode>(
              segments: const <ButtonSegment<LocomotionMode>>[
                ButtonSegment<LocomotionMode>(
                  value: LocomotionMode.gaze,
                  label: Text('Olhar (gaze)'),
                ),
                ButtonSegment<LocomotionMode>(
                  value: LocomotionMode.joystick,
                  label: Text('Joystick'),
                ),
              ],
              selected: <LocomotionMode>{_config.locomotionMode},
              onSelectionChanged: (Set<LocomotionMode> s) =>
                  _apply(_config.copyWith(locomotionMode: s.first)),
            ),
            _SliderRow(
              label: 'Velocidade de caminhada',
              value: _config.walkSpeed,
              min: 1.0,
              max: 5.0,
              unit: 'm/s',
              fractionDigits: 1,
              onChanged: (double v) => _apply(_config.copyWith(walkSpeed: v)),
            ),
            _SliderRow(
              label: 'Head bob',
              value: _config.headBobAmplitude * 1000,
              min: 0,
              max: 60,
              unit: 'mm',
              onChanged: (double v) =>
                  _apply(_config.copyWith(headBobAmplitude: v / 1000)),
            ),
            const SizedBox(height: 8),
            const _SectionTitle('Performance'),
            _SliderRow(
              label: 'Resolucao maxima (pixel ratio)',
              value: _config.maxPixelRatio,
              min: 0.75,
              max: 3.0,
              fractionDigits: 2,
              onChanged: (double v) =>
                  _apply(_config.copyWith(maxPixelRatio: v)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('HUD de diagnostico'),
              subtitle: const Text('FPS, draw calls, orientacao'),
              value: _config.showDebugHud,
              onChanged: (bool v) => _apply(_config.copyWith(showDebugHud: v)),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: widget.onRecenter,
                    child: const Text('Centralizar visao'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onRespawn,
                    child: const Text('Voltar ao inicio'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6FCF97),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.fractionDigits = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              '${value.toStringAsFixed(fractionDigits)}$unit',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8A939C),
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
