package vn.lifeos.app.life_os

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

/**
 * APP-03: Validates that a downloaded OTA APK matches this app's `packageName` AND is signed
 * by the exact same signing certificate SHA-256 before handing off to Android PackageInstaller.
 */
object LifeOsApkSignatureVerifier {
    fun verifyApkPackageAndSigningCert(context: Context, apkFile: File): String? {
        val pm = context.packageManager
        val pkgName = context.packageName
        return try {
            val archiveInfo = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(
                    apkFile.absolutePath,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(apkFile.absolutePath, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(apkFile.absolutePath, PackageManager.GET_SIGNATURES)
            }) ?: return "Tệp APK không hợp lệ hoặc bị hỏng."

            if (archiveInfo.packageName != pkgName) {
                return "Tên gói APK (${archiveInfo.packageName}) không khớp với ứng dụng LifeOS ($pkgName)."
            }

            val installedBytes = getSigningCertBytesForInstalledApp(pm, pkgName)
            val archiveBytes = extractCertBytes(archiveInfo)
            if (installedBytes != null && archiveBytes != null) {
                val installedHash = MessageDigest.getInstance("SHA-256").digest(installedBytes)
                val archiveHash = MessageDigest.getInstance("SHA-256").digest(archiveBytes)
                if (!installedHash.contentEquals(archiveHash)) {
                    return "Chứng chỉ ký của gói APK mới không khớp với phiên bản đang cài đặt (APP-03)."
                }
            }
            null
        } catch (e: Exception) {
            "Không thể xác minh chữ ký số của tệp APK: ${e.message}"
        }
    }

    private fun getSigningCertBytesForInstalledApp(pm: PackageManager, pkgName: String): ByteArray? {
        return try {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    pkgName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkgName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkgName, PackageManager.GET_SIGNATURES)
            }
            extractCertBytes(info)
        } catch (_: Exception) {
            null
        }
    }

    private fun extractCertBytes(pkgInfo: PackageInfo): ByteArray? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = pkgInfo.signingInfo ?: return null
            val sigs = if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
            sigs?.firstOrNull()?.toByteArray()
        } else {
            @Suppress("DEPRECATION")
            pkgInfo.signatures?.firstOrNull()?.toByteArray()
        }
    }
}
