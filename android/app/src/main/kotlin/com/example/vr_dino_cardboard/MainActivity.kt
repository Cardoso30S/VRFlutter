package com.example.vr_dino_cardboard

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

/**
 * Activity da experiencia VR.
 *
 * Alem do padrao do Flutter, fazemos tres ajustes que so podem ser feitos no
 * lado nativo e que impactam diretamente o conforto:
 *
 * 1. `FLAG_KEEP_SCREEN_ON` - redundante com o wakelock_plus, mas garante o
 *    comportamento mesmo se o plugin falhar ao inicializar.
 * 2. `layoutInDisplayCutoutMode = ALWAYS` - permite que o canvas ocupe a area
 *    do notch. Sem isso o sistema deixa uma faixa preta que desalinha o centro
 *    optico de um dos olhos.
 * 3. `setSustainedPerformanceMode` - pede ao SoC uma frequencia estavel em vez
 *    do turbo-e-throttle padrao. Rende um FPS medio menor porem MUITO mais
 *    constante, que e o que importa em VR (frame drops causam enjoo).
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            window.setSustainedPerformanceMode(true)
        }
    }
}
