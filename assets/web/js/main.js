/**
 * Entrypoint da cena WebGL.
 *
 * Responsabilidades:
 *   1. Criar renderer/cena/camera com parametros amigaveis a GPU movel.
 *   2. Montar o mundo e as criaturas.
 *   3. Rodar o `requestAnimationFrame`, aplicando o estado suavizado que veio
 *      do Dart e desenhando em estereo.
 *   4. Reportar prontidao, colisores e metricas de volta para o Flutter.
 *
 * O loop aqui NAO calcula fisica: a fisica e do Dart. Isso evita duas fontes
 * da verdade e mantem a logica testavel no lado nativo.
 */

import * as THREE from 'three';
import { bridge } from './bridge.js';
import { StereoRig } from './stereo_renderer.js';
import { buildWorld } from './scene_builder.js';
import { DinoManager } from './dino_manager.js';

const log = (m) => bridge.log(m);

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------

const canvas = document.getElementById('gl');
let renderer;
try {
  renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: bridge.config.antialias,
    alpha: false,
    stencil: false,
    depth: true,
    powerPreference: 'high-performance',
    // `false` deixa o compositor descartar o buffer apos apresentar - menos
    // trafego de memoria em GPUs de tile (Adreno/Mali/Apple).
    preserveDrawingBuffer: false,
  });
} catch (e) {
  bridge.error('WebGL indisponivel neste dispositivo: ' + e);
  throw e;
}

renderer.setClearColor(0x000000, 1);
renderer.outputColorSpace = THREE.SRGBColorSpace;
// Tone mapping custa instrucoes no fragment shader; o visual "Cretaceo" ja
// vem do gradiente do ceu e da nevoa.
renderer.toneMapping = THREE.NoToneMapping;
renderer.shadowMap.enabled = false;
renderer.info.autoReset = false;

const scene = new THREE.Scene();

// Camera "da cabeca": nunca e renderizada diretamente em estereo, serve de
// base para a StereoCamera.
const camera = new THREE.PerspectiveCamera(
  bridge.config.fov, 1, 0.1, 600,
);
camera.matrixAutoUpdate = true;
scene.add(camera);

const rig = new StereoRig(renderer, bridge.config);

// ---------------------------------------------------------------------------
// Reticulo de mira (filho da camera -> aparece nos dois olhos)
// ---------------------------------------------------------------------------

const reticle = new THREE.Group();
reticle.position.set(0, 0, -2.0);
camera.add(reticle);

const reticleRing = new THREE.Mesh(
  new THREE.RingGeometry(0.014, 0.02, 24),
  new THREE.MeshBasicMaterial({
    color: 0xffffff,
    transparent: true,
    opacity: 0.55,
    depthTest: false,
    depthWrite: false,
    fog: false,
  }),
);
reticleRing.renderOrder = 999;
reticle.add(reticleRing);

// Anel de progresso que preenche quando o gaze-walking esta ativo.
const reticleFill = new THREE.Mesh(
  new THREE.RingGeometry(0.0, 0.012, 20),
  new THREE.MeshBasicMaterial({
    color: 0x8fe3a4,
    transparent: true,
    opacity: 0.0,
    depthTest: false,
    depthWrite: false,
    fog: false,
  }),
);
reticleFill.renderOrder = 1000;
reticle.add(reticleFill);

// ---------------------------------------------------------------------------
// Mundo
// ---------------------------------------------------------------------------

const world = buildWorld(scene, renderer, bridge.config);
const dinos = new DinoManager(scene, bridge.config, log);

// ---------------------------------------------------------------------------
// Redimensionamento
// ---------------------------------------------------------------------------

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, bridge.config.maxPixelRatio);
  const w = window.innerWidth;
  const h = window.innerHeight;
  renderer.setPixelRatio(dpr);
  renderer.setSize(w, h, false);
  // A camera principal mantem o aspect da tela CHEIA; a StereoCamera ja
  // aplica o fator 0.5 internamente.
  camera.aspect = w / Math.max(1, h);
  camera.fov = bridge.config.fov * rig.fovScale;
  camera.updateProjectionMatrix();
  rig.onResize();
}

window.addEventListener('resize', resize, { passive: true });
window.addEventListener('orientationchange', () => setTimeout(resize, 120));
resize();

bridge.onConfig((cfg) => {
  rig.setConfig(cfg);
  resize();
});

bridge.onRecenter(() => {
  // Feedback visual da recentragem: o reticulo pisca.
  reticleRing.material.opacity = 1.0;
});

// ---------------------------------------------------------------------------
// Loop
// ---------------------------------------------------------------------------

const clock = new THREE.Clock();
let frames = 0;
let statsTimer = 0;
let colliderTimer = 0;
let ready = false;

// Colisores estaticos enviados uma vez; os dinamicos (dinossauros) sao
// reenviados periodicamente para que o Dart trate as criaturas como solidas.
function pushColliders() {
  const flat = world.colliders.concat(dinos.getColliders());
  bridge.colliders(flat);
}

function frame() {
  requestAnimationFrame(frame);
  if (bridge.paused) return;

  // `getDelta` ja e monotonico; travamos em 100 ms para o caso de o app
  // voltar do segundo plano.
  const dt = Math.min(clock.getDelta(), 0.1);
  const t = clock.elapsedTime;

  bridge.integrate(dt);
  camera.position.copy(bridge.position);
  camera.quaternion.copy(bridge.quaternion);

  world.update(dt, camera.position);
  dinos.update(dt, t, camera.position, bridge.config.worldRadius);

  // Reticulo: preenche conforme a locomocao ativa.
  const target = bridge.moving ? 0.85 : 0.0;
  reticleFill.material.opacity +=
    (target - reticleFill.material.opacity) * Math.min(1, dt * 8);
  reticleRing.material.opacity +=
    (0.55 - reticleRing.material.opacity) * Math.min(1, dt * 4);

  rig.render(scene, camera);

  // ---- Telemetria ----
  frames++;
  statsTimer += dt;
  if (statsTimer >= 1.0) {
    // `renderer.info` acumula entre os `reset()`; normalizamos por frame
    // (lembrando que cada frame faz 2 render() em estereo).
    const f = Math.max(1, frames);
    bridge.stats({
      fps: frames / statsTimer,
      calls: Math.round(renderer.info.render.calls / f),
      tris: Math.round(renderer.info.render.triangles / f),
      tex: renderer.info.memory.textures,
      prog: renderer.info.programs ? renderer.info.programs.length : 0,
    });
    renderer.info.reset();
    frames = 0;
    statsTimer = 0;
  }

  colliderTimer += dt;
  if (ready && colliderTimer >= 0.5) {
    colliderTimer = 0;
    pushColliders();
  }
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

(async function boot() {
  try {
    await dinos.load();
  } catch (e) {
    log('falha ao povoar dinossauros: ' + e);
  }

  // Pre-compila os shaders antes do primeiro frame: sem isso o primeiro
  // segundo da experiencia engasga enquanto o driver compila os programas -
  // muito perceptivel dentro do visor.
  try {
    renderer.compile(scene, camera);
  } catch (e) {
    log('compile() falhou (nao fatal): ' + e);
  }

  pushColliders();
  ready = true;

  bridge.sceneReady({
    source: window.__VR_ASSET_SOURCE__ || 'unknown',
    three: THREE.REVISION,
    creatures: dinos.creatures.length,
    gltfModels: dinos.loadedModels,
    procedural: dinos.proceduralFallbacks,
    colliders: world.colliders.length / 3,
    maxAnisotropy: renderer.capabilities.getMaxAnisotropy(),
    maxTextureSize: renderer.capabilities.maxTextureSize,
  });

  frame();
})();
