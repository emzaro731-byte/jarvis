package com.emzaro.jarvis

import android.content.Intent
import android.net.Uri
import android.provider.Settings
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
    private var launcherChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("open_ai", false)) {
            launcherChannel?.invokeMethod("openAiFromOverlay", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launcherChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        launcherChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanScreen" -> {
                        val reader = MavisScreenReaderService.instance
                        if (reader == null) {
                            try {
                                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(mapOf("needsPermission" to true, "text" to ""))
                            } catch (e: Exception) { result.error("SCREEN_READER_SETTINGS_FAILED", e.message, null) }
                        } else result.success(mapOf("needsPermission" to false, "text" to reader.scanNow()))
                    }
                    "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(this))
                    "requestOverlayPermission" -> {
                        if (Settings.canDrawOverlays(this)) result.success(true)
                        else {
                            try {
                                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                                result.success(false)
                            } catch (e: Exception) {
                                result.error("OVERLAY_SETTINGS_FAILED", e.message, null)
                            }
                        }
                    }
                    "startOverlay" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            result.error("OVERLAY_PERMISSION_REQUIRED", "Allow display over other apps first.", null)
                        } else {
                            val serviceIntent = Intent(this, JarvisOverlayService::class.java).setAction(JarvisOverlayService.ACTION_START)
                            startService(serviceIntent)
                            result.success(true)
                        }
                    }
                    "stopOverlay" -> {
                        stopService(Intent(this, JarvisOverlayService::class.java).setAction(JarvisOverlayService.ACTION_STOP))
                        result.success(true)
                    }
                    "consumeOpenAiIntent" -> {
                        val shouldOpen = intent?.getBooleanExtra("open_ai", false) == true
                        intent?.removeExtra("open_ai")
                        result.success(shouldOpen)
                    }
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
