# Modelos 3D (.glb / .gltf)

Esta pasta e opcional. **A cena roda sem nenhum arquivo aqui**: cada especie
declarada em `manifest.json` que nao encontrar seu `.glb` cai automaticamente
no dinossauro procedural low-poly equivalente (ver
`assets/web/js/procedural_assets.js`).

## Como adicionar modelos reais

1. Baixe modelos com licenca compativel. Fontes com dinossauros gratuitos:
   - **Quaternius** (CC0, pacote "Ultimate Dinosaurs", ja rigado e animado)
   - **Poly Pizza** (CC0/CC-BY, agregador do antigo Google Poly)
   - **Sketchfab** (filtre por "Downloadable" + licenca CC)
   - **Kenney.nl** (CC0, low-poly)

2. Salve nesta pasta com os nomes usados no `manifest.json`:

   ```
   assets/models/trex.glb
   assets/models/triceratops.glb
   assets/models/brachiosaurus.glb
   assets/models/velociraptor.glb
   ```

3. Ajuste no `manifest.json`:
   - `targetHeight`: altura desejada em metros (o carregador reescala o modelo
     automaticamente, entao a escala original do arquivo nao importa);
   - `animations.idle` / `animations.walk`: nomes EXATOS dos clipes dentro do
     glTF. Se nao encontrar, o carregador usa os clipes 0 e 1.

## Orcamento de performance

Alvo: 60 FPS com renderizacao estereo (ou seja, a cena e desenhada **duas
vezes** por frame).

| Item                         | Recomendado          |
|------------------------------|----------------------|
| Triangulos por dinossauro    | 3k - 15k             |
| Textura por dinossauro       | 1024x1024 (2048 max) |
| Ossos por esqueleto          | <= 64                |
| Total de criaturas na cena   | <= 12                |
| Draw calls por olho          | <= 80                |

Dicas:

- Prefira **um unico material** por criatura (menos draw calls).
- Comprima geometria com **Draco** e texturas com **KTX2/Basis** usando
  `gltf-transform` ou `gltfpack`:

  ```bash
  npx @gltf-transform/cli optimize entrada.glb saida.glb --texture-compress webp
  ```

  Se usar Draco, rode `tool/fetch_web_deps.sh --with-draco` para embutir o
  decodificador em `assets/web/vendor/libs/draco/`.
- Convencao de eixos: o modelo deve olhar para **-Z** e ter os pes em **Y=0**.
  Se ele nascer deitado ou de costas, corrija na exportacao (o carregador nao
  aplica rotacao corretiva de proposito, para nao mascarar assets errados).
