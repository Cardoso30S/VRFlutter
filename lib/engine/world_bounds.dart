import 'dart:math' as math;

/// Cilindro de colisao vertical (arvore, pedra, dinossauro parado).
///
/// Em VR "de pe" um mundo plano com colisores circulares resolve 99% dos casos
/// e custa quase nada - nao ha necessidade de um motor de fisica completo.
class CircleCollider {
  const CircleCollider(this.x, this.z, this.radius);

  final double x;
  final double z;
  final double radius;
}

/// Limites do mapa + resolucao de colisao no plano XZ.
///
/// Os colisores nao sao declarados em Dart: a cena e gerada no lado WebGL
/// (com RNG deterministico) e devolve a lista via [setColliders] assim que
/// termina de montar. Assim existe uma unica fonte da verdade para onde as
/// arvores e pedras realmente estao.
class WorldBounds {
  WorldBounds({required this.radius, this.playerRadius = 0.35});

  /// Raio da arena jogavel, em metros.
  final double radius;

  /// Raio do "corpo" do jogador usado no empurrao de colisao.
  final double playerRadius;

  final List<CircleCollider> _colliders = <CircleCollider>[];

  /// Grade uniforme para broadphase. `cell -> indices`.
  final Map<int, List<int>> _grid = <int, List<int>>{};
  static const double _cellSize = 8.0;

  int get colliderCount => _colliders.length;

  /// Substitui a lista de colisores e reconstroi a grade de broadphase.
  void setColliders(List<CircleCollider> colliders) {
    _colliders
      ..clear()
      ..addAll(colliders);
    _grid.clear();
    for (int i = 0; i < _colliders.length; i++) {
      final CircleCollider c = _colliders[i];
      final int minX = _cellIndex(c.x - c.radius);
      final int maxX = _cellIndex(c.x + c.radius);
      final int minZ = _cellIndex(c.z - c.radius);
      final int maxZ = _cellIndex(c.z + c.radius);
      for (int gx = minX; gx <= maxX; gx++) {
        for (int gz = minZ; gz <= maxZ; gz++) {
          (_grid[_key(gx, gz)] ??= <int>[]).add(i);
        }
      }
    }
  }

  /// Corrige uma posicao candidata, devolvendo-a "empurrada" para fora dos
  /// obstaculos e para dentro do limite do mapa.
  ///
  /// Escreve o resultado em [outXZ] (lista de 2 posicoes) para evitar alocar
  /// um `Vector2` a cada passo de fisica.
  void resolve(double x, double z, List<double> outXZ) {
    double px = x;
    double pz = z;

    // 1) Obstaculos (duas iteracoes resolvem cantos entre dois colisores).
    for (int pass = 0; pass < 2; pass++) {
      bool touched = false;
      final int gx = _cellIndex(px);
      final int gz = _cellIndex(pz);
      for (int ox = -1; ox <= 1; ox++) {
        for (int oz = -1; oz <= 1; oz++) {
          final List<int>? bucket = _grid[_key(gx + ox, gz + oz)];
          if (bucket == null) continue;
          for (final int i in bucket) {
            final CircleCollider c = _colliders[i];
            final double dx = px - c.x;
            final double dz = pz - c.z;
            final double minDist = c.radius + playerRadius;
            final double d2 = dx * dx + dz * dz;
            if (d2 >= minDist * minDist || d2 < 1e-12) continue;
            final double d = math.sqrt(d2);
            final double push = (minDist - d) / d;
            px += dx * push;
            pz += dz * push;
            touched = true;
          }
        }
      }
      if (!touched) break;
    }

    // 2) Limite circular do mapa.
    final double distSq = px * px + pz * pz;
    final double maxDist = radius - playerRadius;
    if (distSq > maxDist * maxDist) {
      final double d = math.sqrt(distSq);
      final double scale = maxDist / d;
      px *= scale;
      pz *= scale;
    }

    outXZ[0] = px;
    outXZ[1] = pz;
  }

  static int _cellIndex(double v) => (v / _cellSize).floor();

  /// Empacota (gx, gz) em uma chave inteira. Faixa util: +-32768 celulas.
  static int _key(int gx, int gz) => (gx << 16) ^ (gz & 0xFFFF);
}
