package com.example.bizzy_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    private val channelName = "bizzy/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApkInfo" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(getApkInfo(path))
                }
                "getInstalledSignature" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    result.success(getInstalledSignature(packageName))
                }
                "getDeviceInfo" -> {
                    result.success(getDeviceInfo())
                }
                "openApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    openApk(path)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getApkInfo(path: String): Map<String, Any?>? {
        val file = File(path)
        if (!file.exists() || !file.canRead()) return null
        val pm = packageManager ?: return null
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info = try {
            pm.getPackageArchiveInfo(path, flags)
        } catch (e: Exception) {
            null
        } ?: return null

        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.toList()
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.toList()
        } ?: emptyList()

        val signatureSha256 = signatures.firstOrNull()?.toByteArray()?.let {
            bytesToSha256(it)
        } ?: ""

        return mapOf(
            "packageName" to (info.packageName ?: ""),
            "versionName" to (info.versionName ?: ""),
            "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode
            },
            "signatureSha256" to signatureSha256,
        )
    }

    private fun getInstalledSignature(packageName: String): String? {
        val pm = packageManager ?: return null
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info = try {
            pm.getPackageInfo(packageName, flags)
        } catch (e: Exception) {
            null
        } ?: return null

        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.toList()
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.toList()
        } ?: emptyList()

        return signatures.firstOrNull()?.toByteArray()?.let {
            bytesToSha256(it)
        }
    }

    private fun getDeviceInfo(): String {
        return "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), " +
                "device=${Build.MANUFACTURER} ${Build.MODEL}, " +
                "package=$packageName"
    }

    private fun openApk(path: String) {
        val file = File(path)
        if (!file.exists()) return
        val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                FileProvider.getUriForFile(
                    this,
                    "$packageName.installFileProvider.install",
                    file
                )
            } catch (e: Exception) {
                null
            }
        } else {
            Uri.fromFile(file)
        }
        if (uri == null) return
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Не удалось открыть установщик.
        }
    }

    private fun bytesToSha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    }
}
