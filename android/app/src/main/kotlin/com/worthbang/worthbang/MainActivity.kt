package com.worthbang.worthbang

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "worthbang/exact_alarm",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "canScheduleExactAlarms" -> {
          val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager
          result.success(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
              alarmManager.canScheduleExactAlarms()
            } else {
              true
            },
          )
        }
        "openExactAlarmSettings" -> {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent =
              Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:$packageName")
              }
            startActivity(intent)
          }
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }
}
