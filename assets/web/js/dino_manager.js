/**
 * Carregamento, povoamento e IA simples dos dinossauros.
 *
 * ## Modelos
 *
 * O manifesto em `assets/models/manifest.json` descreve cada especie. Se o
 * arquivo `.glb` correspondente nao estiver no bundle, cai automaticamente
 * para a versao procedural (`procedural_assets.js`). Isso mantem o projeto
 * executavel sem nenhum asset binario e permite trocar por modelos de verdade
 * sem tocar em codigo.
 *
 * ## IA
 *
 * Maquina de estados minima (parado / andando / girando) com uma direcao alvo
 * sorteada periodicamente. Nao ha pathfinding: as criaturas circulam dentro de
 * um raio ao redor do ponto de origem e se afastam (ou se aproximam, se
 * `curious`) do jogador.
 *
 * ## Custo
 *
 * `AnimationMixer` so e atualizado para criaturas dentro de `ANIM_DISTANCE`;
 * alem de `CULL_DISTANCE` o objeto e escondido (a nevoa ja o tornaria
 * invisivel). Isso evita gastar CPU com esqueletos que ninguem ve.
 */

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { clone as cloneSkinned } from 'three/addons/utils/SkeletonUtils.js';
import { createProceduralDino, makeRng, randRange } from './procedural_assets.js';

const MODELS_BASE = '/assets/models/';
const ANIM_DISTANCE = 55;   // metros
const CULL_DISTANCE = 110;  // metros

/**
 * Configura o GLTFLoader, ativando Draco apenas se os decodificadores
 * estiverem presentes no bundle (modelos comprimidos sao comuns).
 */
async function makeLoader(log) {
  const loader = new GLTFLoader();
  try {
    const probe = await fetch('/assets/web/vendor/libs/draco/draco_decoder.js', {
      method: 'GET',
      cache: 'force-cache',
    });
    if (probe.ok) {
      const { DRACOLoader } = await import('three/addons/loaders/DRACOLoader.js');
      const draco = new DRACOLoader();
      draco.setDecoderPath('/assets/web/vendor/libs/draco/');
      loader.setDRACOLoader(draco);
      log('Draco habilitado');
    }
  } catch (e) {
    // Sem Draco: modelos nao comprimidos continuam funcionando.
  }
  return loader;
}

class Creature {
  /**
   * @param {object} spec entrada do manifesto
   * @param {object} spawn posicao inicial
   * @param {THREE.Object3D} object modelo (glTF ou procedural)
   * @param {?THREE.AnimationMixer} mixer
   * @param {object} clips {idle, walk} ja convertidos em AnimationAction
   * @param {Function} rng
   */
  constructor(spec, spawn, object, mixer, clips, proceduralUpdate, rng) {
    this.spec = spec;
    this.object = object;
    this.mixer = mixer;
    this.clips = clips;
    this.proceduralUpdate = proceduralUpdate;
    this.rng = rng;

    this.home = new THREE.Vector2(spawn.x, spawn.z);
    this.position = new THREE.Vector2(spawn.x, spawn.z);
    this.heading = spawn.heading !== undefined ? spawn.heading : rng() * Math.PI * 2;
    this.targetHeading = this.heading;

    const b = spec.behavior || {};
    this.maxSpeed = b.speed !== undefined ? b.speed : 1.2;
    this.turnRate = b.turnRate !== undefined ? b.turnRate : 0.9;
    this.roamRadius = b.roamRadius !== undefined ? b.roamRadius : 25;
    this.curious = !!b.curious;
    this.personalSpace = b.personalSpace !== undefined ? b.personalSpace : 6;

    this.speed = 0;
    this.wantsToMove = true;
    this.decisionTimer = randRange(rng, 0.5, 4.0);
    this.walkPhase = rng() * Math.PI * 2;
    this.radius = spec.colliderRadius !== undefined ? spec.colliderRadius : 1.2;

    this.object.position.set(spawn.x, spec.yOffset || 0, spawn.z);
    this.object.rotation.y = this.heading;
  }

  /**
   * @param {number} dt
   * @param {number} t tempo absoluto
   * @param {THREE.Vector3} playerPos
   * @param {number} worldRadius
   */
  update(dt, t, playerPos, worldRadius) {
    const dxP = playerPos.x - this.position.x;
    const dzP = playerPos.z - this.position.y;
    const distToPlayer = Math.hypot(dxP, dzP);

    // ---- Decisao -----------------------------------------------------
    this.decisionTimer -= dt;
    if (this.decisionTimer <= 0) {
      this.decisionTimer = randRange(this.rng, 2.5, 7.0);
      // 35% de chance de parar para "pastar"/observar.
      this.wantsToMove = this.rng() > 0.35;
      this.targetHeading = this.rng() * Math.PI * 2;
    }

    // Volta para casa se se afastou demais do territorio.
    const dxH = this.position.x - this.home.x;
    const dzH = this.position.y - this.home.y;
    if (Math.hypot(dxH, dzH) > this.roamRadius) {
      this.targetHeading = Math.atan2(-dxH, -dzH);
      this.wantsToMove = true;
    }

    // Reacao ao jogador.
    if (distToPlayer < this.personalSpace * 3) {
      const towards = Math.atan2(dxP, dzP);
      if (this.curious) {
        // Encara o jogador e para a uma distancia respeitosa.
        this.targetHeading = towards;
        this.wantsToMove = distToPlayer > this.personalSpace;
      } else if (distToPlayer < this.personalSpace * 1.6) {
        // Herbivoro assustado: foge.
        this.targetHeading = towards + Math.PI;
        this.wantsToMove = true;
      }
    }

    // Nao atravessa a muralha do mapa.
    if (this.position.length() > worldRadius - 6) {
      this.targetHeading = Math.atan2(-this.position.x, -this.position.y);
      this.wantsToMove = true;
    }

    // ---- Giro suave --------------------------------------------------
    let diff = this.targetHeading - this.heading;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    const turn = Math.sign(diff) * Math.min(Math.abs(diff), this.turnRate * dt);
    this.heading += turn;

    // ---- Velocidade --------------------------------------------------
    // Nao anda enquanto ainda esta girando muito (evita deslizar de lado).
    const aligned = Math.abs(diff) < 0.6;
    const target = (this.wantsToMove && aligned) ? this.maxSpeed : 0;
    this.speed += (target - this.speed) * Math.min(1, dt * 2.5);

    // O eixo -Z do modelo e a "frente" (convencao glTF).
    this.position.x += Math.sin(this.heading) * this.speed * dt;
    this.position.y += Math.cos(this.heading) * this.speed * dt;

    this.object.position.x = this.position.x;
    this.object.position.z = this.position.y;
    this.object.rotation.y = this.heading;

    // ---- Animacao ----------------------------------------------------
    const intensity = Math.min(1, this.speed / Math.max(0.001, this.maxSpeed));
    // Comprimento da passada proporcional a velocidade: sem "patinacao".
    this.walkPhase += dt * (1.4 + this.speed * 1.8);

    const dist = Math.hypot(playerPos.x - this.position.x,
                            playerPos.z - this.position.y);
    this.object.visible = dist < CULL_DISTANCE;
    if (!this.object.visible) return;

    if (this.mixer && dist < ANIM_DISTANCE) {
      this._crossfade(intensity > 0.15 ? 'walk' : 'idle');
      // Sincroniza a velocidade do clipe com a velocidade real.
      if (this.clips.walk) {
        this.clips.walk.timeScale = 0.6 + intensity * 0.9;
      }
      this.mixer.update(dt);
    } else if (this.proceduralUpdate) {
      this.proceduralUpdate(t, this.walkPhase, intensity);
    }
  }

  _crossfade(name) {
    const next = this.clips[name];
    if (!next || this._active === name) return;
    const prev = this.clips[this._active];
    next.reset().setEffectiveWeight(1).fadeIn(0.35).play();
    if (prev) prev.fadeOut(0.35);
    this._active = name;
  }
}

export class DinoManager {
  constructor(scene, config, log) {
    this.scene = scene;
    this.config = config;
    this.log = log || (() => {});
    this.creatures = [];
    this.loadedModels = 0;
    this.proceduralFallbacks = 0;
    this._rng = makeRng(0xD1405);
  }

  /** Carrega o manifesto e povoa a cena. */
  async load() {
    let manifest;
    try {
      const res = await fetch(MODELS_BASE + 'manifest.json', { cache: 'no-cache' });
      manifest = await res.json();
    } catch (e) {
      this.log('manifest.json ausente ou invalido: ' + e);
      return;
    }

    const loader = await makeLoader(this.log);
    const entries = manifest.dinosaurs || [];

    // Carrega as especies em paralelo; cada falha isolada vira fallback.
    await Promise.all(entries.map((spec) => this._loadSpecies(loader, spec)));

    this.log(
      `dinossauros: ${this.creatures.length} instancias, ` +
      `${this.loadedModels} modelos glTF, ${this.proceduralFallbacks} procedurais`,
    );
  }

  async _loadSpecies(loader, spec) {
    let gltf = null;
    if (spec.model) {
      try {
        gltf = await loader.loadAsync(MODELS_BASE + spec.model);
        this.loadedModels++;
      } catch (e) {
        this.log(`modelo "${spec.model}" indisponivel -> fallback procedural`);
      }
    }

    for (const spawn of (spec.spawns || [])) {
      if (gltf) {
        this.creatures.push(this._instantiateGltf(spec, spawn, gltf));
      } else {
        this.proceduralFallbacks++;
        this.creatures.push(this._instantiateProcedural(spec, spawn));
      }
    }
  }

  _instantiateGltf(spec, spawn, gltf) {
    // `Object3D.clone()` COMPARTILHA o `Skeleton` entre as copias - todas as
    // instancias animariam identicas. `SkeletonUtils.clone` religa os bones de
    // cada copia, que e o que permite varios individuos da mesma especie em
    // fases diferentes da caminhada.
    const object = cloneSkinned(gltf.scene);

    const targetHeight = spec.targetHeight;
    let scale = spec.scale || 1;
    if (targetHeight) {
      const box = new THREE.Box3().setFromObject(object);
      const h = box.max.y - box.min.y;
      if (h > 0.001) scale = targetHeight / h;
    }
    object.scale.setScalar(scale);

    object.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = false;
        o.receiveShadow = false;
        o.frustumCulled = true;
      }
    });

    let mixer = null;
    const clips = {};
    if (gltf.animations && gltf.animations.length) {
      mixer = new THREE.AnimationMixer(object);
      const names = spec.animations || {};
      const find = (wanted, fallbackIndex) => {
        if (wanted) {
          const c = gltf.animations.find(
            (a) => a.name.toLowerCase() === String(wanted).toLowerCase(),
          );
          if (c) return c;
        }
        return gltf.animations[fallbackIndex] || null;
      };
      const idleClip = find(names.idle, 0);
      const walkClip = find(names.walk, Math.min(1, gltf.animations.length - 1));
      if (idleClip) clips.idle = mixer.clipAction(idleClip);
      if (walkClip) clips.walk = mixer.clipAction(walkClip);
      if (clips.idle) clips.idle.play();
    }

    this.scene.add(object);
    return new Creature(spec, spawn, object, mixer, clips, null, this._rng);
  }

  _instantiateProcedural(spec, spawn) {
    const fb = spec.fallback || {};
    const dino = createProceduralDino({
      kind: fb.kind || 'theropod',
      scale: fb.scale || spec.scale || 1,
      color: fb.color !== undefined ? parseInt(fb.color, 16) : undefined,
    });
    this.scene.add(dino.object);
    return new Creature(
      spec, spawn, dino.object, null, {}, dino.update, this._rng,
    );
  }

  /** Colisores dinamicos das criaturas, formato plano [x, z, r, ...]. */
  getColliders() {
    const flat = [];
    for (const c of this.creatures) {
      if (c.spec.solid === false) continue;
      flat.push(c.position.x, c.position.y, c.radius);
    }
    return flat;
  }

  update(dt, t, playerPos, worldRadius) {
    for (const c of this.creatures) {
      c.update(dt, t, playerPos, worldRadius);
    }
  }
}
