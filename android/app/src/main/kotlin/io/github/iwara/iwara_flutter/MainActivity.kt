package io.github.iwara.iwara_flutter

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 继承 AudioServiceActivity 以支持后台播放通知；额外实现画中画。
 */
class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null
    private var autoPip = false
    private var aspect = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iwara/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(pipSupported())
                    "enter" -> {
                        updateAspect(call.argument<Int>("width"), call.argument<Int>("height"))
                        result.success(enterPip())
                    }
                    "setAutoEnter" -> {
                        autoPip = call.argument<Boolean>("enabled") == true
                        updateAspect(call.argument<Int>("width"), call.argument<Int>("height"))
                        applyParams()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun updateAspect(w: Int?, h: Int?) {
        if (w != null && h != null && w > 0 && h > 0) aspect = Rational(w, h)
    }

    private fun buildParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPip)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun applyParams() {
        if (!pipSupported()) return
        try {
            buildParams()?.let { setPictureInPictureParams(it) }
        } catch (_: Exception) {
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            val params = buildParams() ?: return false
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            false
        }
    }

    // Android 12 以下没有 autoEnter，按 Home 时手动进入
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
