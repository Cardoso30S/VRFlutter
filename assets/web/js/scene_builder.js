/**
 * Montagem do ambiente pre-historico.
 *
 * Estrategia de performance:
 *
 * - **InstancedMesh** para toda a vegetacao: milhares de arvores/samambaias
 *   custam 4 draw calls no total, nao 4000.
 * - **Sem sombras dinamicas.** Shadow maps custariam um passe extra por
 *   frame - e em VR sao dois olhos. A profundidade vem da nevoa e do
 *   ambient occlusion "de graca" do gradiente do ceu.
 * - **FogExp2 agressiva** encurta a distancia util de desenho, escondendo o
 *   limite do mapa e reduzindo overdraw.
 */

import * as THREE from 'three';
import {
  makeRng,
  randRange,
  makeGroundTexture,
  makeSkyDome,
  makeTreeGeometries,
  makeCycadGeometries,
  makeFernGeometry,
  makeRockGeometry,
} from './procedural_assets.js';

const SPAWN_CLEAR_RADIUS = 9.0; // area livre ao redor do ponto inicial

/**
 * @param {THREE.Scene} scene
 * @param {THREE.WebGLRenderer} renderer
 * @param {object} config configuracao vinda do Dart
 * @param {number} seed
 * @returns {{colliders: number[], update: Function, dispose: Function}}
 */
export function buildWorld(scene, renderer, config, seed = 20250828) {
  const rng = makeRng(seed);
  const R = config.worldRadius || 90;

  // -----------------------------------------------------------------
  // Atmosfera
  // -----------------------------------------------------------------
  const fogColor = new THREE.Color(0xa8956f);
  scene.background = fogColor;
  scene.fog = new THREE.FogExp2(fogColor, 0.017);

  const sky = makeSkyDome(R * 3.2);
  scene.add(sky.mesh);

  // -----------------------------------------------------------------
  // Luz
  // -----------------------------------------------------------------
  // Intensidades no padrao "physically correct lights" (three r155+).
  const hemi = new THREE.HemisphereLight(0xbfd4e8, 0x6b5a3c, 2.2);
  scene.add(hemi);

  const sun = new THREE.DirectionalLight(0xffe0b2, 2.4);
  sun.position.set(30, 42, -70);
  scene.add(sun);

  // -----------------------------------------------------------------
  // Chao
  // -----------------------------------------------------------------
  const groundTex = makeGroundTexture(renderer, rng);
  const ground = new THREE.Mesh(
    new THREE.CircleGeometry(R * 1.35, 48),
    new THREE.MeshLambertMaterial({ map: groundTex }),
  );
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = false;
  scene.add(ground);

  // -----------------------------------------------------------------
  // Muralha de rocha no limite do mapa
  // -----------------------------------------------------------------
  // Alem de ser o limite visual do cenario, ela explica ao usuario por que
  // ele nao consegue seguir adiante - muito melhor do que uma parede invisivel.
  const wall = new THREE.Mesh(
    new THREE.CylinderGeometry(R + 2, R + 6, 26, 40, 1, true),
    new THREE.MeshLambertMaterial({
      color: 0x6e6152,
      side: THREE.BackSide,
      flatShading: true,
    }),
  );
  wall.position.y = 11;
  scene.add(wall);

  // -----------------------------------------------------------------
  // Vegetacao instanciada
  // -----------------------------------------------------------------
  const colliders = [];   // [x, z, r, ...] enviados ao Dart
  const disposables = [groundTex];

  /** Sorteia uma posicao valida (fora do spawn e sem sobrepor o que ja existe). */
  function scatter(count, minRadius, spacing, onPlace) {
    let placed = 0;
    let guard = 0;
    while (placed < count && guard < count * 24) {
      guard++;
      const a = rng() * Math.PI * 2;
      // sqrt para distribuicao uniforme em area (senao acumula no centro).
      const d = minRadius + Math.sqrt(rng()) * (R - minRadius - 3);
      const x = Math.cos(a) * d;
      const z = Math.sin(a) * d;
      if (x * x + z * z < SPAWN_CLEAR_RADIUS * SPAWN_CLEAR_RADIUS) continue;

      let blocked = false;
      for (let i = 0; i < colliders.length; i += 3) {
        const dx = x - colliders[i];
        const dz = z - colliders[i + 1];
        const min = colliders[i + 2] + spacing;
        if (dx * dx + dz * dz < min * min) { blocked = true; break; }
      }
      if (blocked) continue;

      onPlace(x, z);
      placed++;
    }
    return placed;
  }

  /**
   * Cria um par de InstancedMesh (tronco + copa) e devolve um callback que
   * grava a matriz de cada instancia.
   */
  function makeInstancedPlant(geos, materials, count) {
    const trunkMesh = new THREE.InstancedMesh(geos.trunk, materials.trunk, count);
    const canopyMesh = new THREE.InstancedMesh(geos.canopy, materials.canopy, count);
    for (const m of [trunkMesh, canopyMesh]) {
      m.instanceMatrix.setUsage(THREE.StaticDrawUsage);
      m.frustumCulled = false; // instancias espalhadas: o bounding box cobre tudo
      scene.add(m);
    }
    disposables.push(geos.trunk, geos.canopy, materials.trunk, materials.canopy);
    return { trunkMesh, canopyMesh };
  }

  const dummy = new THREE.Object3D();

  // --- Coniferas altas -------------------------------------------------
  const TREE_COUNT = 130;
  const treeGeos = makeTreeGeometries();
  const treeMats = {
    trunk: new THREE.MeshLambertMaterial({ color: 0x4a3b2a, flatShading: true }),
    canopy: new THREE.MeshLambertMaterial({ color: 0x33502e, flatShading: true }),
  };
  const trees = makeInstancedPlant(treeGeos, treeMats, TREE_COUNT);
  let treeIndex = 0;
  scatter(TREE_COUNT, 12, 3.6, (x, z) => {
    const s = randRange(rng, 0.8, 1.55);
    dummy.position.set(x, 0, z);
    dummy.rotation.set(0, rng() * Math.PI * 2, 0);
    dummy.scale.setScalar(s);
    dummy.updateMatrix();
    trees.trunkMesh.setMatrixAt(treeIndex, dummy.matrix);
    trees.canopyMesh.setMatrixAt(treeIndex, dummy.matrix);
    treeIndex++;
    colliders.push(x, z, 0.45 * s);
  });
  trees.trunkMesh.count = treeIndex;
  trees.canopyMesh.count = treeIndex;
  trees.trunkMesh.instanceMatrix.needsUpdate = true;
  trees.canopyMesh.instanceMatrix.needsUpdate = true;

  // --- Cicadaceas ------------------------------------------------------
  const CYCAD_COUNT = 90;
  const cycadGeos = makeCycadGeometries(rng);
  const cycadMats = {
    trunk: new THREE.MeshLambertMaterial({ color: 0x5c4a33, flatShading: true }),
    canopy: new THREE.MeshLambertMaterial({
      color: 0x4a6b33,
      flatShading: true,
      side: THREE.DoubleSide,
    }),
  };
  const cycads = makeInstancedPlant(cycadGeos, cycadMats, CYCAD_COUNT);
  let cycadIndex = 0;
  scatter(CYCAD_COUNT, 8, 2.2, (x, z) => {
    const s = randRange(rng, 0.9, 1.8);
    dummy.position.set(x, 0, z);
    dummy.rotation.set(0, rng() * Math.PI * 2, 0);
    dummy.scale.setScalar(s);
    dummy.updateMatrix();
    cycads.trunkMesh.setMatrixAt(cycadIndex, dummy.matrix);
    cycads.canopyMesh.setMatrixAt(cycadIndex, dummy.matrix);
    cycadIndex++;
    colliders.push(x, z, 0.55 * s);
  });
  cycads.trunkMesh.count = cycadIndex;
  cycads.canopyMesh.count = cycadIndex;
  cycads.trunkMesh.instanceMatrix.needsUpdate = true;
  cycads.canopyMesh.instanceMatrix.needsUpdate = true;

  // --- Samambaias rasteiras (sem colisao: o jogador atravessa) ----------
  const FERN_COUNT = 900;
  const fernGeo = makeFernGeometry(rng);
  const fernMat = new THREE.MeshLambertMaterial({
    color: 0x54783a,
    flatShading: true,
    side: THREE.DoubleSide,
  });
  const ferns = new THREE.InstancedMesh(fernGeo, fernMat, FERN_COUNT);
  ferns.instanceMatrix.setUsage(THREE.StaticDrawUsage);
  ferns.frustumCulled = false;
  scene.add(ferns);
  disposables.push(fernGeo, fernMat);
  for (let i = 0; i < FERN_COUNT; i++) {
    const a = rng() * Math.PI * 2;
    const d = Math.sqrt(rng()) * (R - 2);
    dummy.position.set(Math.cos(a) * d, 0, Math.sin(a) * d);
    dummy.rotation.set(0, rng() * Math.PI * 2, 0);
    dummy.scale.setScalar(randRange(rng, 0.6, 1.4));
    dummy.updateMatrix();
    ferns.setMatrixAt(i, dummy.matrix);
  }
  ferns.instanceMatrix.needsUpdate = true;

  // --- Pedras ----------------------------------------------------------
  const ROCK_COUNT = 70;
  const rockGeo = makeRockGeometry(rng);
  const rockMat = new THREE.MeshLambertMaterial({
    color: 0x7b7364,
    flatShading: true,
  });
  const rocks = new THREE.InstancedMesh(rockGeo, rockMat, ROCK_COUNT);
  rocks.instanceMatrix.setUsage(THREE.StaticDrawUsage);
  rocks.frustumCulled = false;
  scene.add(rocks);
  disposables.push(rockGeo, rockMat);
  let rockIndex = 0;
  scatter(ROCK_COUNT, 6, 1.6, (x, z) => {
    const s = randRange(rng, 0.45, 2.2);
    dummy.position.set(x, s * 0.35, z);
    dummy.rotation.set(rng() * 0.4, rng() * Math.PI * 2, rng() * 0.4);
    dummy.scale.setScalar(s);
    dummy.updateMatrix();
    rocks.setMatrixAt(rockIndex, dummy.matrix);
    rockIndex++;
    if (s > 0.9) colliders.push(x, z, s * 0.85);
  });
  rocks.count = rockIndex;
  rocks.instanceMatrix.needsUpdate = true;

  // -----------------------------------------------------------------

  return {
    colliders,
    sky,
    /**
     * O domo do ceu acompanha o jogador para nunca ser alcancado.
     * `matrixAutoUpdate` esta desligado: atualizamos a matriz na mao.
     */
    update(dt, cameraPosition) {
      sky.mesh.position.copy(cameraPosition);
      sky.mesh.updateMatrix();
    },
    dispose() {
      for (const d of disposables) if (d && d.dispose) d.dispose();
    },
  };
}
