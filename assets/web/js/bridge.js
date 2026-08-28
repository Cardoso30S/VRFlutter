/**
 * Ponte JavaScript <-> Flutter.
 *
 * O Dart e a fonte da verdade para orientacao e posicao; este modulo apenas
 * recebe os pacotes, guarda o alvo mais recente e expoe uma aplicacao
 * *suavizada* para o loop de render.
 *
 * Motivo da suavizacao: a ponte e assincrona e a taxa dela nao e a mesma do
 * `requestAnimationFrame`. Aplicar o valor cru causaria micro-travamentos
 * visiveis. Posicao usa suavizacao exponencial mais forte (muda devagar);
 * orientacao usa uma slerp bem curta, porque latencia de head-tracking e o
 * defeito mais perceptivel em VR.
 */

import * as THREE from 'three';

const POS_SMOOTH = 18.0;   // 1/s
const ROT_SMOOTH = 45.0;   // 1/s

class VrBridge {
  constructor() {
    /** Alvo recebido do Dart. */
    this.targetPosition = new THREE.Vector3(0, 1.68, 6);
    this.targetQuaternion = new THREE.Quaternion();

    /** Valor aplicado na camera (suavizado). */
    this.position = this.targetPosition.clone();
    this.quaternion = this.targetQuaternion.clone();

    this.speed = 0;
    this.moving = false;
    this.paused = false;

    /** Configuracao vinda do Dart (ver VrConfig.toRendererJson). */
    this.config = {
      stereo: true,
      distortion: true,
      ipd: 0.064,
      fov: 75,
      k1: 0.22,
      k2: 0.24,
      lensCenterOffset: 0.0,
      maxPixelRatio: 1.5,
      antialias: false,
      worldRadius: 90,
      eyeHeight: 1.68,
    };

    this._configListeners = [];
    this._recenterListeners = [];
    this._firstPacket = true;
  }

  /** Registra callback para mudancas de configuracao. */
  onConfig(fn) { this._configListeners.push(fn); }

  /** Registra callback para o evento de recentragem. */
  onRecenter(fn) { this._recenterListeners.push(fn); }

  /**
   * Recebe o pacote de estado do Dart.
   * Assinatura posicional (nao objeto) para minimizar o custo da ponte.
   */
  setState(x, y, z, qx, qy, qz, qw, speed, moving) {
    this.targetPosition.set(x, y, z);
    this.targetQuaternion.set(qx, qy, qz, qw);
    this.speed = speed;
    this.moving = moving === 1 || moving === true;

    if (this._firstPacket) {
      this._firstPacket = false;
      this.position.copy(this.targetPosition);
      this.quaternion.copy(this.targetQuaternion);
    }
  }

  /** Interpola em direcao ao alvo. Chamado uma vez por frame de render. */
  integrate(dt) {
    const ap = 1 - Math.exp(-POS_SMOOTH * dt);
    const ar = 1 - Math.exp(-ROT_SMOOTH * dt);
    this.position.lerp(this.targetPosition, ap);
    this.quaternion.slerp(this.targetQuaternion, ar);
  }

  applyConfig(cfg) {
    Object.assign(this.config, cfg || {});
    for (const fn of this._configListeners) fn(this.config);
  }

  triggerRecenter() {
    for (const fn of this._recenterListeners) fn();
  }

  // ---- Saidas para o Dart ------------------------------------------------

  static call(handler, payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler(handler, payload);
      }
    } catch (e) {
      // Rodando fora do Flutter (debug em browser): ignora.
    }
  }

  log(msg) { VrBridge.call('vrLog', String(msg)); }
  error(msg) { VrBridge.call('vrError', String(msg)); }
  sceneReady(info) { VrBridge.call('vrSceneReady', info); }
  stats(s) { VrBridge.call('vrStats', s); }

  /** Colisores achatados como [x, z, r, x, z, r, ...]. */
  colliders(flat) { VrBridge.call('vrColliders', flat); }
}

export const bridge = new VrBridge();

// API global consumida pelo Dart via evaluateJavascript.
window.VRB = {
  s: (x, y, z, qx, qy, qz, qw, speed, moving) =>
    bridge.setState(x, y, z, qx, qy, qz, qw, speed, moving),
  configure: (cfg) => bridge.applyConfig(cfg),
  recenter: () => bridge.triggerRecenter(),
  setPaused: (v) => { bridge.paused = !!v; },
};
