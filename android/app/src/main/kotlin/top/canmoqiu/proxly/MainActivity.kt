package top.canmoqiu.proxly

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.system.exitProcess

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "proxly/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restartApp" -> {
                        restartApp()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun restartApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }

        if (launchIntent != null) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                1001,
                launchIntent,
                PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.set(
                AlarmManager.RTC,
                System.currentTimeMillis() + 350L,
                pendingIntent
            )
        }

        finishAndRemoveTask()
        exitProcess(0)
    }
}
