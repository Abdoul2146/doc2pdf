package com.magnatrus.doc2pdf

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var renderPlugin: RenderPdfPlugin? = null
    private var legacyWriteRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        renderPlugin = RenderPdfPlugin(flutterEngine, this)
    }

    /**
     * API 26-28 only: ask for `WRITE_EXTERNAL_STORAGE` so a converted PDF can be
     * published into the public Documents folder. Fire and forget; if the user
     * declines, the conversion still succeeds and the engine reports a save
     * warning instead. Android 10+ uses MediaStore and never prompts.
     */
    fun requestLegacyWritePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return

        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted || legacyWriteRequested) return

        legacyWriteRequested = true
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_LEGACY_WRITE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_LEGACY_WRITE) {
            // Allow one retry per conversion attempt if the user declined.
            legacyWriteRequested = false
        }
    }

    override fun onDestroy() {
        renderPlugin?.dispose()
        renderPlugin = null
        super.onDestroy()
    }

    private companion object {
        const val REQUEST_LEGACY_WRITE = 7711
    }
}
