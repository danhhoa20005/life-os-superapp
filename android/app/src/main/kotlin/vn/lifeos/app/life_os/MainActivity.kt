package vn.lifeos.app.life_os

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val methodChannelName = "vn.lifeos.app/bank_listener_methods"
    private val eventChannelName = "vn.lifeos.app/bank_listener_events"
    private val appUpdaterChannelName = "vn.lifeos.app/app_updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> {
                        result.success(isNotificationServiceEnabled())
                    }
                    "openPermissionSettings" -> {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    "updateConfig" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val packages = call.argument<List<String>>("allowedPackages") ?: emptyList()
                        val prefs = applicationContext.getSharedPreferences(
                            BankNotificationListenerService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        prefs.edit()
                            .putBoolean(BankNotificationListenerService.KEY_ENABLED, enabled)
                            .putStringSet(BankNotificationListenerService.KEY_PACKAGES, packages.toSet())
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    BankNotificationListenerService.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    BankNotificationListenerService.eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdaterChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledAppVersion" -> {
                        try {
                            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.getPackageInfo(
                                    packageName,
                                    PackageManager.PackageInfoFlags.of(0)
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(packageName, 0)
                            }
                            val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                pkgInfo.longVersionCode.toInt()
                            } else {
                                @Suppress("DEPRECATION")
                                pkgInfo.versionCode
                            }
                            result.success(
                                mapOf(
                                    "versionName" to (pkgInfo.versionName ?: "1.0.0"),
                                    "buildNumber" to buildNumber,
                                    "packageName" to packageName,
                                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
                                )
                            )
                        } catch (e: Exception) {
                            result.error("VERSION_ERROR", e.message, null)
                        }
                    }
                    "getUpdateCacheDir" -> {
                        val dir = File(cacheDir, "ota_updates")
                        if (!dir.exists()) {
                            dir.mkdirs()
                        }
                        result.success(dir.absolutePath)
                    }
                    "canRequestPackageInstalls" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "Đường dẫn tệp APK trống.", null)
                            return@setMethodCallHandler
                        }
                        val apkFile = File(filePath)
                        if (!apkFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Không tìm thấy tệp APK đã tải.", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(permIntent)
                            result.success("PERMISSION_REQUIRED")
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
                            result.success("INSTALLER_LAUNCHED")
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "URL trống.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(browserIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val cn = ComponentName(this, BankNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }
}
