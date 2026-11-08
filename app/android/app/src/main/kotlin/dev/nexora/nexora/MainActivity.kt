package dev.nexora.nexora

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexora/background")
            .setMethodCallHandler { call, result ->
                val title = call.argument<String>("title") ?: "NEXORA travaille…"
                val text = call.argument<String>("text") ?: ""
                val done = call.argument<Int>("done") ?: 0
                val total = call.argument<Int>("total") ?: 0
                try {
                    when (call.method) {
                        "start" -> {
                            askNotifications()
                            val intent = Intent(this, WorkService::class.java)
                                .putExtra("title", title)
                                .putExtra("text", text)
                                .putExtra("done", done)
                                .putExtra("total", total)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        }
                        "update" -> {
                            WorkService.current?.update(title, text, done, total)
                            result.success(WorkService.current != null)
                        }
                        "stop" -> {
                            WorkService.current?.finish()
                            result.success(true)
                        }
                        "notify" -> {
                            Notifs.done(this, title, text)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // Ex. : Android refuse de démarrer le service depuis l'arrière-plan.
                    result.error("background", e.message, null)
                }
            }
    }

    /** Android 13+ : la notification de travail a besoin de l'accord de l'utilisateur. */
    private fun askNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
        }
    }
}
