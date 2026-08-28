# VR Dino Cardboard

Experiência de Realidade Virtual estilo **Google Cardboard** em Flutter:
estereoscopia side-by-side, head-tracking por giroscópio e um ambiente
pré-histórico explorável com dinossauros.

> **Status:** código completo e revisado, porém **não compilado nem executado**
> (o ambiente onde foi escrito não tem o SDK Flutter). Rode `tool/setup.sh`
> seguido de `flutter analyze && flutter test` antes do primeiro deploy —
> veja [Verificação pendente](#verificação-pendente).

---

## 1. Decisão de arquitetura: por que WebView + Three.js

Foram avaliadas três abordagens para renderização 3D em Flutter:

| Abordagem | Estéreo | glTF/GLB | Animação por esqueleto | Maturidade | Veredito |
|---|---|---|---|---|---|
| **`model_viewer_plus`** | ❌ | ✅ | ✅ | alta | Visualizador de UM modelo. Não expõe câmera, cena nem loop de render. Inviável. |
| **`flutter_scene` (Impeller)** | ❌ nativo | ⚠️ exige conversão para `.model` | parcial | experimental | Promissor, mas hoje não há câmera estéreo, pós-processamento nem instancing. Reescreveríamos meio motor. |
| **Three.js em `flutter_inappwebview`** | ✅ `StereoCamera` | ✅ `GLTFLoader` | ✅ `AnimationMixer` | muito alta | **Escolhida.** |

Complemento importante: **WebXR não resolve o problema.** O `immersive-vr` de
visor Cardboard foi removido do Chrome para Android; o que restou depende de
hardware dedicado. Fazer a estereoscopia "na mão" com `StereoCamera` +
scissor é o caminho que realmente funciona num celular dentro de um visor de
papelão.

### Divisão de responsabilidades

O ponto central do desenho é **não deixar a lógica dentro do WebView**:

```
┌─────────────────────────── Flutter / Dart ───────────────────────────┐
│                                                                       │
│  sensors_plus ──▶ HeadTracker ──▶ quaternion da câmera                │
│  (gyro+accel)     (filtro Mahony)         │                           │
│                                            ▼                          │
│  toque / joystick / gamepad ──▶ LocomotionController (passo fixo)      │
│                                            │  posição + colisão       │
│                                            ▼                          │
│                                       VrFrameState                    │
│                                            │                          │
└────────────────────────────────────────────┼──────────────────────────┘
                                             │  1 chamada JS por frame
                                             ▼
┌──────────────────────── WebView / Three.js ──────────────────────────┐
│  bridge.js  ──▶ suavização/slerp ──▶ camera.position/quaternion       │
│  scene_builder.js  (terreno, névoa, vegetação instanciada)            │
│  dino_manager.js   (GLB + IA de perambulação + fallback procedural)   │
│  stereo_renderer.js (StereoCamera + pré-distorção de lente)           │
└───────────────────────────────────────────────────────────────────────┘
                                             │  colisores, FPS, logs
                                             └──────────▶ de volta ao Dart
```

**Por que os sensores ficam no Dart e não no JS?** O `DeviceOrientationEvent`
do navegador chega a ~30-40 Hz, já filtrado pelo SO, com latência extra e
exigindo `requestPermission()` no iOS. Lendo o sensor nativo em
`SensorInterval.gameInterval` (~50 Hz) e fundindo em Dart, controlamos o
filtro e cortamos latência — o defeito mais percebido em VR.

**Por que a física fica no Dart e não no JS?** Uma única fonte da verdade,
testável com `flutter test` (ver `test/vr_math_test.dart`), sem duplicar
estado dos dois lados da ponte.

**Por que o JS interpola?** A ponte é assíncrona e não roda na cadência do
`requestAnimationFrame`. O `bridge.js` guarda o último pacote como *alvo* e
converge para ele por frame (`lerp` para posição, `slerp` curta para
orientação). Se um pacote atrasa, o render continua fluido em vez de travar.

---

## 2. Head-tracking: como a orientação é calculada

`lib/sensors/head_tracker.dart` implementa um **filtro complementar de
Mahony**:

1. O **giroscópio** integra a orientação pelo mapa exponencial — preciso no
   curto prazo, mas acumula deriva.
2. O **acelerômetro** dá uma referência absoluta de "para cima" sempre que o
   módulo do vetor está perto de 1 g (fora dessa janela há aceleração linear e
   a leitura enganaria). O erro `e = m × p` entre a gravidade medida e a
   predita realimenta a velocidade angular com ganho `Kp`.
3. O termo integral `Ki` estima e cancela o **bias** do giroscópio.

Resultado: **pitch e roll ficam absolutos** (sem deriva). O **yaw deriva**,
porque não há referência absoluta — o magnetômetro é inútil aqui, já que a
maioria dos visores Cardboard tem um ímã no gatilho. A correção é o
`recenter()`, exposto como **toque duplo na tela**.

### Referenciais e o quaternion de alinhamento

`lib/sensors/orientation_mapping.dart` documenta a conversão completa. Em
resumo, com o aparelho em paisagem e o topo à esquerda:

```
direita da câmera = -Y do aparelho
cima da câmera    = +X do aparelho
trás da câmera    = +Z do aparelho     →  rotação de -90° em torno de Z

qCâmera = qYawOffset · qCorpo · qAlinhamento
```

Se a imagem aparecer de cabeça para baixo ou o giro responder invertido,
troque **Encaixe do aparelho no visor** no menu de calibragem — é o sintoma
clássico de o celular ter sido inserido girado 180°.

---

## 3. Locomoção

`lib/engine/locomotion_controller.dart` roda com **passo fixo de 1/120 s**
(no máximo 6 sub-passos por frame). Integrar com `dt` variável — e o `Ticker`
entrega 200 ms depois de um GC — faria o jogador atravessar árvores.

**Opção A — Gaze walking (padrão).** Andar para frente quando o usuário olha
abaixo de −22° *ou* mantém o toque na tela. A intensidade tem rampa suave
entre o limiar e 20° abaixo dele: o liga/desliga brusco é desconfortável.

**Opção B — Joystick / gamepad.** Arraste em qualquer ponto da tela cria um
joystick virtual na origem do toque (`lib/engine/input/virtual_joystick.dart`).
Controles Bluetooth são lidos como teclado HID
(`lib/engine/input/gamepad_input.dart`) — é assim que a esmagadora maioria dos
gamepads e "clickers" de mercado se anuncia, e funciona nos dois sistemas sem
código nativo.

**Colisão.** Círculos no plano XZ + limite circular do mapa, com broadphase em
grade uniforme (`lib/engine/world_bounds.dart`). Os colisores **não são
declarados em Dart**: a cena é gerada no lado WebGL com RNG determinístico e
devolve a lista pela ponte — uma única fonte da verdade para onde as árvores
realmente estão. Os dinossauros são reenviados a cada 0,5 s, então também
bloqueiam o jogador.

**Head bob** existe, mas com amplitude pequena e ajustável (0 desliga):
oscilação vertical é um gatilho conhecido de enjoo em VR.

---

## 4. Renderização estéreo e distorção de lente

`assets/web/js/stereo_renderer.js`.

- Usa **`THREE.StereoCamera`**, que vem no core do three.js (o `StereoEffect`
  fica em `examples/jsm`). Ela aplica translação de ±IPD/2 **e projeção
  off-axis** (frustum assimétrico). Esse detalhe separa "3D confortável" de
  "3D que dá dor de cabeça": rotacionar as câmeras uma em direção à outra
  (*toe-in*) introduz paralaxe vertical nas bordas.
- A câmera principal mantém o *aspect* da tela **cheia** — `StereoCamera.aspect`
  já é `0.5` e faz a divisão internamente.
- Cada olho é desenhado com `setScissor`/`setViewport` na metade
  correspondente.

**Pré-distorção.** As lentes do Cardboard produzem *pincushion*; compensamos
renderizando com *barrel*: para cada pixel de saída em raio `r`, amostramos a
cena em `r · (1 + k1·r² + k2·r⁴)`. É **um** passe de tela cheia sobre **um**
render target contendo os dois olhos — mais barato que dois targets e dois
passes. O FOV é ampliado por um fator derivado de `k1+k2` para que a periferia
não fique preta.

Padrões `k1 = 0.22`, `k2 = 0.24` correspondem ao Cardboard v1. Ajuste no menu
até que uma linha reta na periferia pareça reta dentro do visor.

---

## 5. Cenário

`assets/web/js/scene_builder.js` + `procedural_assets.js`.

- **Céu:** domo com gradiente de três paradas + halo solar largo, em shader.
  Um cubemap seria mais bonito e custaria 6 texturas no bundle e VRAM; quem
  vende a profundidade aqui é a névoa.
- **Névoa:** `FogExp2` agressiva. Esconde o limite do mapa, reduz *overdraw* e
  dá o clima úmido do Cretáceo.
- **Chão:** textura gerada em canvas 256×256 (terra, tufos de vegetação,
  cascalho), repetida 48× com anisotropia — o chão é visto em ângulo rasante.
- **Vegetação:** coníferas, cicadáceas, samambaias e pedras em
  **`InstancedMesh`**. ~1.200 objetos custam **4 draw calls**, não 1.200.
- **Limite do mapa:** uma muralha de rocha. Muito melhor do que uma parede
  invisível — o usuário *entende* por que não passa.
- **Sem sombras dinâmicas.** Shadow map é um passe extra por frame, e em
  estéreo isso dobra.

### Dinossauros

`assets/web/js/dino_manager.js` lê `assets/models/manifest.json`, carrega os
`.glb` e, **para cada espécie cujo arquivo não existir, cai automaticamente em
um dinossauro procedural low-poly articulado** (terópode, saurópode ou
ceratopsiano). Ou seja: **o projeto roda sem baixar nenhum asset binário**, e
trocar por modelos reais não exige tocar em código — só colocar o arquivo e
ajustar `targetHeight` no manifesto. Veja `assets/models/README.md`.

A IA é uma máquina de estados mínima (parado / andando / girando) com direção
alvo sorteada, retorno ao território de origem, e reação ao jogador: espécies
com `curious: true` encaram e se aproximam até a distância de respeito; as
demais fogem. `AnimationMixer` só é atualizado dentro de 55 m; além de 110 m o
objeto é escondido (a névoa já o esconderia).

---

## 6. Como rodar

> **O primeiro comando é obrigatório.** Este repositório **não contém**
> `android/` nem `ios/` — só os arquivos de plataforma específicos da VR
> (`AndroidManifest.xml`, `Info.plist`, `MainActivity.kt`). O resto é
> boilerplate que o Flutter gera e que muda a cada versão do SDK.
> Sem gerá-lo, `flutter run` falha com **"Build failed due to use of deleted
> Android v1 embedding"** — o Flutter não acha `android/build.gradle`, conclui
> que o projeto não usa Gradle, procura o manifesto no caminho antigo
> (`android/AndroidManifest.xml`) e assume a v1.

**Linux / macOS**

```bash
git clone <este-repo> && cd VRFlutter

tool/setup.sh                    # 1) gera android/ e ios/
tool/fetch_web_deps.sh           # 2) embute o three.js (+ --with-draco se precisar)
flutter analyze && flutter test  # 3)
flutter run --release            # 4) SEMPRE em release
```

**Windows (PowerShell)**

```powershell
git clone <este-repo>; cd VRFlutter

powershell -ExecutionPolicy Bypass -File tool\setup.ps1
powershell -ExecutionPolicy Bypass -File tool\fetch_web_deps.ps1
flutter analyze; flutter test
flutter run --release
```

Os scripts `.sh` **não** funcionam no PowerShell sem WSL com uma distro
instalada; use os `.ps1`. Eles fazem exatamente a mesma coisa.

`setup.sh`/`setup.ps1` rodam `flutter create` **sem `--overwrite`**, então
todo arquivo já existente é preservado — `pubspec.yaml`, `lib/`, `README.md` e
os arquivos de plataforma acima. Nunca acrescente `--overwrite`.

Sem o passo 2 o app ainda funciona: `index.html` detecta a ausência de
`assets/web/vendor/` e cai para o CDN jsDelivr (exige rede no primeiro
carregamento). Os arquivos são gravados **planos** na raiz de `vendor/`, que já
está declarada no `pubspec.yaml` — nenhum ajuste é necessário.

### Se o Gradle falhar

Os arquivos em `android/` são **boilerplate gerado pelo `flutter create`**, não
código deste projeto. O erro aparece quando a máquina tem um Android Gradle
Plugin novo demais para o template do Flutter:

```
Line 07: android {
         ^ 'fun Project.android(...)' is deprecated. Replaced by
           com.android.build.api.dsl.ApplicationExtension.
```

Isso **não é um aviso**. No Kotlin, uma API marcada com `DeprecationLevel.ERROR`
vira erro de compilação — por isso o Gradle conta a depreciação entre os
"N errors". O template usa o bloco `android { }` clássico, que o AGP 9 marca
nesse nível. **Nenhuma edição do `build.gradle.kts` resolve**: é preciso usar
um AGP 8.x.

```powershell
powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1   # Windows
```
```bash
tool/fix_gradle.sh                                            # Linux/macOS
```

O script escolhe o par AGP/Kotlin conforme o Gradle do wrapper (AGP 8.11+ é o
primeiro que suporta Gradle 9), restaura o bloco `kotlin { compilerOptions }`
canônico do template e imprime um diagnóstico com as quatro versões que
importam. É idempotente. Para fixar versões específicas:

```powershell
powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1 -Agp 8.7.3 -Kotlin 2.1.0
```

Depois: `flutter clean && flutter run --release`.

### Requisitos mínimos

| | |
|---|---|
| Android | 7.0 (API 24) · System WebView 89+ · OpenGL ES 3.0 |
| iOS | 16.4+ (import maps no WKWebView) |
| Hardware | giroscópio + acelerômetro |

### Controles

| Gesto | Ação |
|---|---|
| Girar a cabeça | Olhar (3-DoF) |
| Olhar para baixo | Andar para frente (modo gaze) |
| Toque contínuo | Andar / correr |
| Arrastar | Joystick virtual (modo joystick) |
| **Toque duplo** | **Centralizar a visão** (corrige a deriva de yaw) |
| Setas / WASD / D-pad | Locomoção por gamepad Bluetooth |
| Ícone ⚙ (canto superior esquerdo) | Menu de calibragem |

---

## 7. Orçamento de performance (60 FPS)

Lembre que **tudo é desenhado duas vezes por frame**.

| Decisão | Motivo |
|---|---|
| `maxPixelRatio` limitado a 1.5 | Telas 1440p com DPR 3.0 derrubam o FPS pela metade. É o ajuste de maior impacto — está no menu. |
| `antialias: false` | MSAA é caro em GPUs de tile. A pré-distorção já suaviza a periferia. |
| `MeshLambertMaterial` | Sem BRDF PBR no fragment shader. |
| `InstancedMesh` na vegetação | 4 draw calls em vez de 1.200. |
| `renderer.compile()` no boot | Sem isso o driver compila os shaders durante o primeiro segundo — engasgo muito perceptível dentro do visor. |
| `setSustainedPerformanceMode(true)` (Android) | FPS médio menor, porém **muito mais constante**. Frame drop causa enjoo; FPS médio alto não impede enjoo. |
| Sem sombras, sem tone mapping | Custo por pixel, dobrado pelo estéreo. |
| Backpressure na ponte | Se o `evaluateJavascript` anterior não retornou, o frame é **descartado**, não enfileirado. Enfileirar acumularia latência de head-tracking. |
| `CADisableMinimumFrameDurationOnPhone` (iOS) | Libera 120 Hz em telas ProMotion. |

O HUD de diagnóstico (menu → *HUD de diagnóstico*) mostra FPS, draw calls,
triângulos, orientação, posição e frames descartados na ponte.

---

## 8. Permissões declaradas

**Android** (`android/app/src/main/AndroidManifest.xml`) — sensores de
movimento **não** exigem permissão em runtime, apenas as `uses-feature`:

- `android.hardware.sensor.gyroscope` / `.accelerometer` (`required="true"`)
- `glEsVersion 0x00030000` (WebGL 2)
- `INTERNET` — necessária mesmo offline: o `InAppLocalhostServer` abre um
  socket local
- `WAKE_LOCK`, `VIBRATE`
- `android:hardwareAccelerated="true"`, `largeHeap="true"`
- `networkSecurityConfig` liberando cleartext **apenas para o loopback**, em
  vez de reabrir `usesCleartextTraffic` para a internet inteira

**iOS** (`ios/Runner/Info.plist`):

- `NSMotionUsageDescription` — **sem esta chave o app é encerrado pelo sistema**
  na primeira leitura do giroscópio
- `NSAppTransportSecurity › NSAllowsLocalNetworking` — libera o servidor local
- `UIRequiredDeviceCapabilities` com `gyroscope` e `accelerometer`
- Somente paisagem, status bar oculta, `UIRequiresFullScreen`

---

## 9. Estrutura

```
lib/
  main.dart                          entrypoint, trava orientação antes do 1º frame
  app.dart                           tema escuro (luz extra vaza pelas lentes)
  core/
    vr_config.dart                   todos os parâmetros de calibragem
    vr_preferences.dart              persistência (shared_preferences)
  sensors/
    head_tracker.dart                ① filtro complementar giroscópio+acelerômetro
    orientation_mapping.dart         referenciais, alinhamento, Euler YXZ
  engine/
    locomotion_controller.dart       ③ loop de física com passo fixo
    world_bounds.dart                colisão circular + broadphase em grade
    vr_state.dart                    pacote de estado serializado
    input/virtual_joystick.dart      joystick overlay
    input/gamepad_input.dart         gamepad Bluetooth via teclado HID
  webview/
    vr_scene_view.dart               ② InAppWebView + servidor local
    vr_web_bridge.dart               ponte Dart↔JS com backpressure
  ui/
    vr_screen.dart                   orquestração (Ticker único)
    hud_overlay.dart                 HUD duplicado nos dois olhos
    settings_sheet.dart              menu de calibragem

assets/web/
  index.html                         carregador vendor→CDN + import map
  js/bridge.js                       recepção e suavização do estado
  js/stereo_renderer.js              ② StereoCamera + pré-distorção
  js/scene_builder.js                terreno, névoa, vegetação instanciada
  js/procedural_assets.js            texturas, plantas e dinossauros procedurais
  js/dino_manager.js                 glTF, IA de perambulação, LOD
  js/main.js                         renderer, loop, telemetria

assets/models/                       .glb opcionais + manifest.json
test/vr_math_test.dart               testes de orientação, colisão e input
tool/                                setup, deps web e fix do Gradle (.sh e .ps1)
```

① leitor de giroscópio e cálculo de orientação · ② widget da cena VR com
split-screen · ③ loop de física/movimentação — os três entregáveis Dart
pedidos.

---

## Verificação pendente

O código foi escrito e revisado sem SDK Flutter disponível no ambiente. Foi
validado o que era possível validar estaticamente:

- ✅ Sintaxe de todos os módulos JavaScript (`node --check`)
- ✅ `manifest.json`, `AndroidManifest.xml`, `network_security_config.xml`,
  `Info.plist`
- ❌ **`flutter analyze` — não executado**
- ❌ **`flutter test` — não executado**
- ❌ **Nenhum build ou teste em dispositivo físico**

Rode antes do primeiro deploy:

```bash
flutter analyze
flutter test
flutter run --release
```

## Limitações conhecidas

- **Yaw deriva** ao longo de sessões longas (sem magnetômetro, por decisão de
  projeto). Toque duplo recentraliza.
- **3-DoF apenas** — rotação, sem translação da cabeça. É o limite físico do
  Cardboard.
- **Sem áudio.** Áudio espacial (`PositionalAudio` do three.js) é a próxima
  adição de maior impacto na imersão.
- **iOS < 16.4** não roda: o WKWebView não suporta import maps.
- Terreno é **plano**; não há heightmap nem gravidade.
