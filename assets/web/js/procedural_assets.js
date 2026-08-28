/**
 * Geracao procedural de cenario e criaturas.
 *
 * Dois motivos para gerar tudo em codigo em vez de embutir binarios:
 *
 * 1. **O projeto roda sem baixar nada.** Modelos de dinossauro tem licenca e
 *    peso; aqui eles sao opcionais (ver `dino_manager.js`). Sem os `.glb`
 *    a cena continua completa, so que com criaturas low-poly.
 * 2. **Peso do APK/IPA.** Texturas de chao e ceu geradas em canvas custam
 *    zero bytes no bundle e alguns milissegundos no boot.
 *
 * Regra de performance aplicada em todo o arquivo: geometria de poucos
 * poligonos, materiais `MeshLambertMaterial` (sem BRDF PBR) e nenhuma sombra
 * dinamica - o que mantem o custo por olho baixo o suficiente para 60 FPS em
 * GPUs moveis de gama media.
 */

import * as THREE from 'three';

// ---------------------------------------------------------------------------
// RNG deterministico
// ---------------------------------------------------------------------------

/**
 * Mulberry32: PRNG de 32 bits, rapido e com boa distribuicao.
 * Deterministico de proposito - a mesma seed gera a mesma floresta, o que
 * permite que os colisores enviados ao Dart sempre batam com o que e visto.
 */
export function makeRng(seed) {
  let a = seed >>> 0;
  return function rng() {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const randRange = (rng, min, max) => min + rng() * (max - min);

// ---------------------------------------------------------------------------
// Texturas procedurais
// ---------------------------------------------------------------------------

/**
 * Textura de solo: terra batida com manchas de vegetacao e cascalho.
 * Gerada em canvas 256x256 e repetida - suficiente sob a nevoa.
 */
export function makeGroundTexture(renderer, rng) {
  const S = 256;
  const c = document.createElement('canvas');
  c.width = c.height = S;
  const g = c.getContext('2d');

  g.fillStyle = '#5b4a32';
  g.fillRect(0, 0, S, S);

  // Manchas grandes de terra clara/escura.
  for (let i = 0; i < 240; i++) {
    const r = randRange(rng, 6, 34);
    const shade = Math.floor(randRange(rng, 52, 96));
    g.fillStyle = `rgba(${shade + 30},${shade + 14},${shade - 12},0.35)`;
    g.beginPath();
    g.arc(rng() * S, rng() * S, r, 0, Math.PI * 2);
    g.fill();
  }
  // Tufos de vegetacao.
  for (let i = 0; i < 420; i++) {
    const green = Math.floor(randRange(rng, 60, 120));
    g.fillStyle = `rgba(${Math.floor(green * 0.5)},${green},${Math.floor(green * 0.36)},0.5)`;
    g.beginPath();
    g.arc(rng() * S, rng() * S, randRange(rng, 2, 7), 0, Math.PI * 2);
    g.fill();
  }
  // Cascalho.
  for (let i = 0; i < 900; i++) {
    const v = Math.floor(randRange(rng, 90, 150));
    g.fillStyle = `rgba(${v},${v - 10},${v - 26},0.28)`;
    g.fillRect(rng() * S, rng() * S, 1.5, 1.5);
  }

  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(48, 48);
  tex.colorSpace = THREE.SRGBColorSpace;
  // Anisotropia melhora muito a leitura do chao em angulo rasante, que e
  // exatamente o caso em VR de pe.
  tex.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
  return tex;
}

/**
 * Ceu pre-historico: domo com gradiente + sol difuso, tudo em shader.
 *
 * Um cubemap seria mais bonito, porem custa 6 texturas no bundle e memoria
 * de VRAM. O gradiente casa com a `FogExp2` da cena, que e o que realmente
 * vende a profundidade.
 */
export function makeSkyDome(radius) {
  const uniforms = {
    uTop: { value: new THREE.Color(0x2c4a6b) },
    uMid: { value: new THREE.Color(0xc98f5a) },
    uBottom: { value: new THREE.Color(0x6d5a41) },
    uSunDir: { value: new THREE.Vector3(0.35, 0.26, -0.9).normalize() },
    uSunColor: { value: new THREE.Color(0xffd9a0) },
  };

  const material = new THREE.ShaderMaterial({
    uniforms,
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
    vertexShader: `
      varying vec3 vDir;
      void main() {
        vDir = normalize(position);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      precision mediump float;
      uniform vec3 uTop, uMid, uBottom, uSunColor;
      uniform vec3 uSunDir;
      varying vec3 vDir;
      void main() {
        vec3 d = normalize(vDir);
        float h = d.y;
        // Gradiente em tres paradas: zenite -> horizonte -> abaixo do horizonte.
        vec3 sky = mix(uMid, uTop, clamp(h * 1.6, 0.0, 1.0));
        sky = mix(uBottom, sky, smoothstep(-0.22, 0.06, h));
        // Halo solar largo (o ar do Cretaceo era umido: sol difuso).
        float sun = pow(max(dot(d, normalize(uSunDir)), 0.0), 18.0);
        float glow = pow(max(dot(d, normalize(uSunDir)), 0.0), 3.0) * 0.28;
        gl_FragColor = vec4(sky + uSunColor * (sun * 0.9 + glow), 1.0);
      }
    `,
  });

  const mesh = new THREE.Mesh(new THREE.SphereGeometry(radius, 24, 16), material);
  mesh.frustumCulled = false;
  mesh.renderOrder = -1000;
  mesh.matrixAutoUpdate = false;
  return { mesh, uniforms };
}

// ---------------------------------------------------------------------------
// Geometrias de vegetacao
// ---------------------------------------------------------------------------

/**
 * Conifera/araucaria estilizada: tronco + tres coroas conicas.
 * Devolve geometrias separadas para virarem dois `InstancedMesh`.
 */
export function makeTreeGeometries() {
  const trunk = new THREE.CylinderGeometry(0.16, 0.28, 5.2, 6, 1, false);
  trunk.translate(0, 2.6, 0);

  const crowns = [];
  const specs = [
    { r: 1.9, h: 2.4, y: 3.4 },
    { r: 1.5, h: 2.2, y: 4.6 },
    { r: 1.0, h: 1.9, y: 5.7 },
  ];
  for (const s of specs) {
    const c = new THREE.ConeGeometry(s.r, s.h, 7, 1, false);
    c.translate(0, s.y, 0);
    crowns.push(c);
  }
  const canopy = mergeGeometries(crowns);
  return { trunk, canopy };
}

/**
 * Cicadacea / samambaia arborescente: caule curto e coroa de frondes.
 */
export function makeCycadGeometries(rng) {
  const trunk = new THREE.CylinderGeometry(0.22, 0.3, 1.5, 6, 1, false);
  trunk.translate(0, 0.75, 0);

  const fronds = [];
  const n = 9;
  for (let i = 0; i < n; i++) {
    // Fronde = plano estreito inclinado e girado em torno do eixo.
    const f = new THREE.PlaneGeometry(0.5, 2.6, 1, 3);
    f.translate(0, 1.3, 0);
    const m = new THREE.Matrix4();
    const tilt = new THREE.Matrix4().makeRotationX(randRange(rng, 0.55, 0.95));
    const spin = new THREE.Matrix4().makeRotationY((i / n) * Math.PI * 2);
    m.multiplyMatrices(spin, tilt);
    m.setPosition(0, 1.4, 0);
    f.applyMatrix4(m);
    fronds.push(f);
  }
  return { trunk, canopy: mergeGeometries(fronds) };
}

/** Samambaia rasteira (moita baixa, usada em grande quantidade). */
export function makeFernGeometry(rng) {
  const blades = [];
  const n = 6;
  for (let i = 0; i < n; i++) {
    const b = new THREE.PlaneGeometry(0.22, 1.05, 1, 2);
    b.translate(0, 0.52, 0);
    const m = new THREE.Matrix4();
    const tilt = new THREE.Matrix4().makeRotationX(randRange(rng, 0.35, 0.85));
    const spin = new THREE.Matrix4().makeRotationY((i / n) * Math.PI * 2 + rng());
    m.multiplyMatrices(spin, tilt);
    blades.push(b.applyMatrix4(m));
  }
  return mergeGeometries(blades);
}

/** Pedra: icosaedro com vertices deslocados (aparencia facetada). */
export function makeRockGeometry(rng) {
  const g = new THREE.IcosahedronGeometry(1, 0);
  const pos = g.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const s = randRange(rng, 0.72, 1.28);
    pos.setXYZ(i, pos.getX(i) * s, pos.getY(i) * s * 0.75, pos.getZ(i) * s);
  }
  g.computeVertexNormals();
  return g;
}

/**
 * Une varias BufferGeometry nao-indexadas em uma so.
 *
 * Implementacao local (em vez de `three/addons/utils/BufferGeometryUtils.js`)
 * para reduzir uma dependencia de rede: precisamos apenas de position/normal/uv.
 */
export function mergeGeometries(geometries) {
  const parts = geometries.map((g) => (g.index ? g.toNonIndexed() : g));
  let total = 0;
  for (const g of parts) total += g.attributes.position.count;

  const position = new Float32Array(total * 3);
  const normal = new Float32Array(total * 3);
  const uv = new Float32Array(total * 2);

  let v = 0;
  for (const g of parts) {
    const p = g.attributes.position;
    const nAttr = g.attributes.normal || null;
    const uvAttr = g.attributes.uv || null;
    for (let i = 0; i < p.count; i++, v++) {
      position[v * 3] = p.getX(i);
      position[v * 3 + 1] = p.getY(i);
      position[v * 3 + 2] = p.getZ(i);
      if (nAttr) {
        normal[v * 3] = nAttr.getX(i);
        normal[v * 3 + 1] = nAttr.getY(i);
        normal[v * 3 + 2] = nAttr.getZ(i);
      }
      if (uvAttr) {
        uv[v * 2] = uvAttr.getX(i);
        uv[v * 2 + 1] = uvAttr.getY(i);
      }
    }
  }

  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(position, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(normal, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  if (!geometries.some((g) => g.attributes.normal)) out.computeVertexNormals();
  return out;
}

// ---------------------------------------------------------------------------
// Dinossauro procedural (fallback quando nao ha .glb)
// ---------------------------------------------------------------------------

/**
 * Monta um dinossauro low-poly articulado.
 *
 * A animacao NAO usa `AnimationMixer`: como as juntas sao criadas aqui,
 * animar por codigo (senoides defasadas) sai mais barato e evita carregar
 * clipes. `update()` recebe a fase da caminhada, entao a passada acompanha a
 * velocidade real da criatura.
 *
 * @param {object} spec
 * @param {'theropod'|'sauropod'|'ceratopsian'} spec.kind
 * @param {number} spec.scale
 * @param {number} spec.color
 */
export function createProceduralDino(spec) {
  const kind = spec.kind || 'theropod';
  const color = new THREE.Color(spec.color !== undefined ? spec.color : 0x7a6a4f);
  const mat = new THREE.MeshLambertMaterial({ color, flatShading: true });
  const bellyMat = new THREE.MeshLambertMaterial({
    color: color.clone().offsetHSL(0, -0.08, 0.16),
    flatShading: true,
  });

  // `root` recebe posicao/escala/rotacao do gerenciador de cena.
  // `rig` guarda o corpo e absorve o balanco vertical da caminhada, para que
  // as duas coisas nao briguem pelo mesmo transform.
  const root = new THREE.Group();
  const rig = new THREE.Group();
  root.add(rig);
  const parts = {};

  const capsule = (r, len, m) =>
    new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 3, 6), m || mat);
  const box = (w, h, d, m) =>
    new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m || mat);

  if (kind === 'sauropod') {
    // Corpo massivo, pescoco e cauda longos, quatro patas colunares.
    const body = capsule(1.5, 2.6);
    body.rotation.z = Math.PI / 2;
    body.position.y = 3.4;
    rig.add(body);

    const neck = new THREE.Group();
    neck.position.set(0, 4.1, -1.6);
    rig.add(neck);
    parts.neck = neck;
    const neckMesh = capsule(0.42, 4.2);
    neckMesh.rotation.x = -0.55;
    neckMesh.position.set(0, 1.7, -0.9);
    neck.add(neckMesh);
    const head = box(0.62, 0.55, 1.15, bellyMat);
    head.position.set(0, 3.5, -2.1);
    neck.add(head);

    const tail = new THREE.Group();
    tail.position.set(0, 3.4, 1.8);
    rig.add(tail);
    parts.tail = tail;
    const tailMesh = capsule(0.4, 5.0);
    tailMesh.rotation.x = 1.42;
    tailMesh.position.set(0, -0.35, 2.4);
    tail.add(tailMesh);

    parts.legs = [];
    const legX = 1.05, legZ = 1.35;
    for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
      const leg = new THREE.Group();
      leg.position.set(sx * legX, 3.0, sz * legZ);
      rig.add(leg);
      const upper = capsule(0.36, 1.7);
      upper.position.y = -1.1;
      leg.add(upper);
      const foot = box(0.72, 0.34, 0.9, bellyMat);
      foot.position.y = -2.25;
      leg.add(foot);
      parts.legs.push(leg);
    }
  } else if (kind === 'ceratopsian') {
    // Corpo baixo e largo, cabeca com folho e chifres.
    const body = capsule(1.0, 1.9);
    body.rotation.z = Math.PI / 2;
    body.position.y = 1.75;
    rig.add(body);

    const headGroup = new THREE.Group();
    headGroup.position.set(0, 1.9, -1.85);
    rig.add(headGroup);
    parts.neck = headGroup;

    const frill = new THREE.Mesh(
      new THREE.CylinderGeometry(1.25, 0.85, 0.18, 8, 1, false),
      bellyMat,
    );
    frill.rotation.x = Math.PI / 2 - 0.25;
    frill.position.set(0, 0.42, 0.15);
    headGroup.add(frill);

    const skull = box(0.78, 0.68, 1.3);
    skull.position.set(0, 0.06, -0.66);
    headGroup.add(skull);

    const beak = new THREE.Mesh(new THREE.ConeGeometry(0.3, 0.6, 5), bellyMat);
    beak.rotation.x = -Math.PI / 2;
    beak.position.set(0, -0.06, -1.42);
    headGroup.add(beak);

    for (const sx of [-1, 1]) {
      const horn = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.85, 5), bellyMat);
      horn.position.set(sx * 0.3, 0.42, -0.95);
      horn.rotation.x = -0.85;
      headGroup.add(horn);
    }

    const tail = new THREE.Group();
    tail.position.set(0, 1.8, 1.5);
    rig.add(tail);
    parts.tail = tail;
    const tailMesh = capsule(0.3, 1.7);
    tailMesh.rotation.x = 1.5;
    tailMesh.position.set(0, -0.2, 0.95);
    tail.add(tailMesh);

    parts.legs = [];
    for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
      const leg = new THREE.Group();
      leg.position.set(sx * 0.78, 1.5, sz * 0.95);
      rig.add(leg);
      const upper = capsule(0.26, 0.85);
      upper.position.y = -0.6;
      leg.add(upper);
      const foot = box(0.5, 0.24, 0.62, bellyMat);
      foot.position.y = -1.18;
      leg.add(foot);
      parts.legs.push(leg);
    }
  } else {
    // Teropode bipede (T-Rex/Alossauro): torso inclinado, cauda de contrapeso.
    const body = capsule(0.95, 2.2);
    body.rotation.x = Math.PI / 2 - 0.18;
    body.position.set(0, 2.85, -0.15);
    rig.add(body);

    const neck = new THREE.Group();
    neck.position.set(0, 3.5, -1.5);
    rig.add(neck);
    parts.neck = neck;

    const neckMesh = capsule(0.42, 0.95);
    neckMesh.rotation.x = 0.9;
    neckMesh.position.set(0, 0.25, -0.35);
    neck.add(neckMesh);

    const skull = box(0.72, 0.78, 1.9);
    skull.position.set(0, 0.52, -1.35);
    neck.add(skull);

    const jaw = box(0.66, 0.3, 1.6, bellyMat);
    jaw.position.set(0, 0.1, -1.35);
    neck.add(jaw);
    parts.jaw = jaw;

    // Dentes: um unico plano serrilhado e barato e le bem a distancia.
    const teeth = new THREE.Mesh(
      new THREE.ConeGeometry(0.06, 0.26, 3),
      new THREE.MeshLambertMaterial({ color: 0xe8e0cf, flatShading: true }),
    );
    for (let i = 0; i < 6; i++) {
      const t = teeth.clone();
      t.position.set((i % 2 ? 0.26 : -0.26), 0.24, -0.85 - (i >> 1) * 0.34);
      t.rotation.x = Math.PI;
      neck.add(t);
    }

    for (const sx of [-1, 1]) {
      const eye = new THREE.Mesh(
        new THREE.SphereGeometry(0.09, 6, 5),
        new THREE.MeshBasicMaterial({ color: 0xd8b23a }),
      );
      eye.position.set(sx * 0.3, 0.72, -1.05);
      neck.add(eye);
    }

    const tail = new THREE.Group();
    tail.position.set(0, 2.9, 1.0);
    rig.add(tail);
    parts.tail = tail;
    const tailMesh = capsule(0.36, 3.1);
    tailMesh.rotation.x = 1.48;
    tailMesh.position.set(0, -0.18, 1.7);
    tail.add(tailMesh);

    // Bracinhos.
    for (const sx of [-1, 1]) {
      const arm = capsule(0.11, 0.5, bellyMat);
      arm.position.set(sx * 0.55, 3.0, -0.95);
      arm.rotation.x = 0.6;
      rig.add(arm);
    }

    parts.legs = [];
    for (const sx of [-1, 1]) {
      const leg = new THREE.Group();
      leg.position.set(sx * 0.55, 2.5, 0.05);
      rig.add(leg);
      const thigh = capsule(0.34, 0.9);
      thigh.position.y = -0.6;
      leg.add(thigh);
      const shin = capsule(0.2, 0.95, bellyMat);
      shin.position.set(0, -1.6, 0.12);
      leg.add(shin);
      const foot = box(0.44, 0.22, 0.88, bellyMat);
      foot.position.set(0, -2.2, -0.16);
      leg.add(foot);
      parts.legs.push(leg);
    }
  }

  const scale = spec.scale || 1;
  root.scale.setScalar(scale);

  // Altura aproximada usada pelo gerenciador para o reticulo/rotulo.
  const bbox = new THREE.Box3().setFromObject(root);
  const height = bbox.max.y - bbox.min.y;

  /**
   * @param {number} t tempo absoluto (s)
   * @param {number} phase fase da passada (rad); avanca com a velocidade
   * @param {number} intensity 0 parado .. 1 andando
   */
  function update(t, phase, intensity) {
    const swing = Math.sin(phase);
    if (parts.legs) {
      for (let i = 0; i < parts.legs.length; i++) {
        // Patas opostas em contra-fase (diagonal nos quadrupedes).
        const sign = (i % 2 === 0) ? 1 : -1;
        const quadOffset = parts.legs.length === 4 && i >= 2 ? Math.PI : 0;
        parts.legs[i].rotation.x =
          Math.sin(phase + quadOffset) * sign * 0.55 * intensity;
      }
    }
    if (parts.tail) {
      parts.tail.rotation.y = Math.sin(t * 0.9 + phase * 0.5) * 0.12 +
        swing * 0.14 * intensity;
      parts.tail.rotation.x = Math.sin(t * 0.6) * 0.04;
    }
    if (parts.neck) {
      parts.neck.rotation.x = Math.sin(t * 0.7) * 0.05 - swing * 0.06 * intensity;
      parts.neck.rotation.y = Math.sin(t * 0.35) * 0.16;
    }
    if (parts.jaw) {
      // Respiracao/rugido ocasional.
      const open = Math.max(0, Math.sin(t * 0.42)) ** 6;
      parts.jaw.rotation.x = open * 0.35;
    }
    // Balanco vertical do corpo com a passada.
    rig.position.y = Math.abs(Math.sin(phase)) * 0.05 * intensity;
  }

  return { object: root, update, height, isProcedural: true };
}
