package com.emzaro.jarvis

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.emzaro.jarvis/launcher"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApps" -> {
                        try {
                            val intent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
                            val apps = packageManager.queryIntentActivities(intent, 0)
                                .mapNotNull { info ->
                                    val packageName = info.activityInfo?.packageName ?: return@mapNotNull null
                                    val label = info.loadLabel(packageManager)?.toString() ?: packageName
                                    val icon = try {
                                        val drawable = info.loadIcon(packageManager)
                                        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                                            drawable.bitmap
                                        } else {
                                            val b = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                                            val canvas = Canvas(b)
                                            drawable.setBounds(0, 0, canvas.width, canvas.height)
                                            drawable.draw(canvas)
                                            b
                                        }
                                        val output = ByteArrayOutputStream()
                                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                                        Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
                                    } catch (_: Exception) { "" }
                                    mapOf("label" to label, "packageName" to packageName, "icon" to icon)
                                }
                                .distinctBy { it["packageName"] }
                                .sortedBy { (it["label"] as? String)?.lowercase() ?: "" }
                            result.success(apps)
                        } catch (e: Exception) {
                            result.error("APP_LIST_FAILED", e.message, null)
                        }
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("INVALID_PACKAGE", "Missing package name", null)
                        } else {
                            try {
                                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                                if (launchIntent == null) {
                                    result.error("APP_NOT_LAUNCHABLE", "No launch activity found", null)
                                } else {
                                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(launchIntent)
                                    result.success(true)
                                }
                            } catch (e: Exception) {
                                result.error("LAUNCH_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
