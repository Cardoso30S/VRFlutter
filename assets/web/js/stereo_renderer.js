/**
 * Renderizador estereo side-by-side com pre-distorcao de lente.
 *
 * ## Estereoscopia
 *
 * Usa `THREE.StereoCamera` (que ja vem no core do three.js, ao contrario do
 * `StereoEffect` que fica em examples/jsm). Ela deriva duas cameras da camera
 * principal aplicando:
 *   - translacao de +-IPD/2 no eixo X local;
 *   - projecao off-axis (frustum assimetrico) com convergencia em `focus`.
 *
 * A projecao off-axis e o detalhe que separa "3D confortavel" de "3D que da
 * dor de cabeca": rotacionar as cameras uma em direcao a outra (toe-in)
 * introduz paralaxe vertical nas bordas.
 *
 * `StereoCamera.aspect` ja e 0.5, entao a camera principal deve manter o
 * aspect da tela CHEIA.
 *
 * ## Pre-distorcao
 *
 * As lentes do Cardboard tem distorcao pincushion. Compensamos renderizando
 * a imagem com distorcao barril: para cada pixel de saida em raio `r`,
 * amostramos a cena em `r * (1 + k1*r^2 + k2*r^4)`.
 *
 * Feito em UM passo de tela cheia sobre um unico render target contendo os
 * dois olhos (mais barato do que dois targets + dois passes).
 */

import * as THREE from 'three';

const DISTORT_VERT = `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

const DISTORT_FRAG = `
precision mediump float;
uniform sampler2D tDiffuse;
uniform float uK1;
uniform float uK2;
uniform float uCenterOffset;   // deslocamento do centro optico (meia-tela)
uniform float uEyeAspect;      // largura/altura de UM olho
varying vec2 vUv;

void main() {
  // 0.0 = olho esquerdo, 1.0 = olho direito
  float eye = step(0.5, vUv.x);

  // Coordenada local do olho, em 0..1
  vec2 uv = vec2(fract(vUv.x * 2.0), vUv.y);

  // Centro da lente: deslocado para dentro em cada olho.
  vec2 center = vec2(0.5 + mix(uCenterOffset, -uCenterOffset, eye), 0.5);

  // Corrige o aspecto para que a distorcao seja radial de verdade.
  vec2 d = uv - center;
  d.x *= uEyeAspect;

  float r2 = dot(d, d);
  float f = 1.0 + uK1 * r2 + uK2 * r2 * r2;

  vec2 src = center + vec2(d.x / uEyeAspect, d.y) * f;

  // Fora do frame renderizado -> preto (evita esticar a borda).
  if (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  gl_FragColor = texture2D(tDiffuse, vec2((src.x + eye) * 0.5, src.y));
}
`;

export class StereoRig {
  /**
   * @param {THREE.WebGLRenderer} renderer
   * @param {object} config configuracao inicial (ver bridge.config)
   */
  constructor(renderer, config) {
    this.renderer = renderer;
    this.config = config;

    this.stereoCamera = new THREE.StereoCamera();
    this.stereoCamera.aspect = 0.5;
    this.stereoCamera.eyeSep = config.ipd;

    this._size = new THREE.Vector2();
    this._target = null;

    // Cena do passe de distorcao: um triangulo/quad em NDC.
    this._quadScene = new THREE.Scene();
    this._quadCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this._quadMaterial = new THREE.ShaderMaterial({
      uniforms: {
        tDiffuse: { value: null },
        uK1: { value: config.k1 },
        uK2: { value: config.k2 },
        uCenterOffset: { value: config.lensCenterOffset },
        uEyeAspect: { value: 1.0 },
      },
      vertexShader: DISTORT_VERT,
      fragmentShader: DISTORT_FRAG,
      depthTest: false,
      depthWrite: false,
    });
    this._quad = new THREE.Mesh(
      new THREE.PlaneGeometry(2, 2),
      this._quadMaterial,
    );
    this._quad.frustumCulled = false;
    this._quadScene.add(this._quad);
  }

  setConfig(config) {
    this.config = config;
    this.stereoCamera.eyeSep = config.ipd;
    this._quadMaterial.uniforms.uK1.value = config.k1;
    this._quadMaterial.uniforms.uK2.value = config.k2;
    this._quadMaterial.uniforms.uCenterOffset.value = config.lensCenterOffset;
    this._ensureTarget(true);
  }

  /**
   * Fator de ampliacao do FOV usado quando a distorcao esta ligada.
   *
   * A pre-distorcao "puxa" o conteudo periferico para dentro; sem renderizar
   * um pouco mais largo, as bordas do campo de visao ficariam pretas.
   */
  get fovScale() {
    if (!this.config.distortion) return 1.0;
    const s = 1.0 + 0.55 * (this.config.k1 + this.config.k2);
    return Math.min(Math.max(s, 1.0), 1.45);
  }

  _ensureTarget(force) {
    if (!this.config.distortion) {
      if (this._target) { this._target.dispose(); this._target = null; }
      return;
    }
    this.renderer.getDrawingBufferSize(this._size);
    const w = Math.max(2, this._size.x | 0);
    const h = Math.max(2, this._size.y | 0);
    if (this._target && !force &&
        this._target.width === w && this._target.height === h) {
      return;
    }
    if (this._target) this._target.dispose();
    this._target = new THREE.WebGLRenderTarget(w, h, {
      minFilter: THREE.LinearFilter,
      magFilter: THREE.LinearFilter,
      format: THREE.RGBAFormat,
      depthBuffer: true,
      stencilBuffer: false,
      // `type` padrao (UnsignedByte) e o mais rapido em GPUs moveis.
    });
    this._quadMaterial.uniforms.tDiffuse.value = this._target.texture;
    this._quadMaterial.uniforms.uEyeAspect.value = (w * 0.5) / h;
  }

  onResize() { this._ensureTarget(true); }

  /**
   * @param {THREE.Scene} scene
   * @param {THREE.PerspectiveCamera} camera camera "da cabeca"
   */
  render(scene, camera) {
    const r = this.renderer;
    r.getSize(this._size);
    const w = this._size.x;
    const h = this._size.y;

    scene.updateMatrixWorld();
    if (camera.parent === null) camera.updateMatrixWorld();

    if (!this.config.stereo) {
      r.setRenderTarget(null);
      r.setScissorTest(false);
      r.setViewport(0, 0, w, h);
      r.render(scene, camera);
      return;
    }

    this._ensureTarget(false);
    this.stereoCamera.update(camera);

    const dest = this.config.distortion ? this._target : null;
    r.setRenderTarget(dest);
    r.clear();
    r.setScissorTest(true);

    // Olho esquerdo.
    r.setScissor(0, 0, w / 2, h);
    r.setViewport(0, 0, w / 2, h);
    r.render(scene, this.stereoCamera.cameraL);

    // Olho direito.
    r.setScissor(w / 2, 0, w / 2, h);
    r.setViewport(w / 2, 0, w / 2, h);
    r.render(scene, this.stereoCamera.cameraR);

    r.setScissorTest(false);

    if (dest) {
      r.setRenderTarget(null);
      r.setViewport(0, 0, w, h);
      r.clear();
      r.render(this._quadScene, this._quadCamera);
    }
  }

  dispose() {
    if (this._target) this._target.dispose();
    this._quad.geometry.dispose();
    this._quadMaterial.dispose();
  }
}
