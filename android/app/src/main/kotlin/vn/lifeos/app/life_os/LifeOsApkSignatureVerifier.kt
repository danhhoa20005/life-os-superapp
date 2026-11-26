package vn.lifeos.app.life_os

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

enum class ApkSignatureStatus {
    MATCH,
    MISMATCH,
    UNREADABLE
}

data class SignerIdentitySnapshot(
    val activeCertSha256s: List<String>,
    val lineageCertSha256s: List<String> = emptyList(),
    val hasMultipleSigners: Boolean = false
)

data class ApkSignatureVerificationResult(
    val status: ApkSignatureStatus,
    val errorCode: String? = null,
    val reasonVi: String? = null,
    val archiveSignerSha256s: List<String> = emptyList(),
    val installedSignerSha256s: List<String> = emptyList()
) {
    val isMatch: Boolean get() = status == ApkSignatureStatus.MATCH
}

/**
 * APP-03: Fail-closed tri-state OTA APK signature verifier (`MATCH` / `MISMATCH` / `UNREADABLE`).
 * Validates package identity, active signing certificates, and API 28+ `SigningInfo` rotation lineage.
 * Only `MATCH` may proceed to Android PackageInstaller.
 */
object LifeOsApkSignatureVerifier {
    private val sha256HexRegex = Regex("^[0-9a-f]{64}$")

    fun normalizeSha256Hex(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        var cleaned = raw.trim().lowercase()
        if (cleaned.startsWith("sha256:")) {
            cleaned = cleaned.substring(7).trim()
        }
        cleaned = cleaned.replace(":", "").replace("-", "").replace(" ", "")
        return if (sha256HexRegex.matches(cleaned)) cleaned else null
    }

    fun sha256Hex(certBytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(certBytes)
        return digest.joinToString(separator = "") { b -> "%02x".format(b) }
    }

    /**
     * Pure comparison & channel policy evaluation (JVM unit-testable without Android Context).
     */
    fun evaluateVerification(
        expectedPackageName: String,
        archivePackageName: String?,
        installedIdentity: SignerIdentitySnapshot?,
        archiveIdentity: SignerIdentitySnapshot?,
        distributionFlavor: String = "github",
        expectedChannelCertSha256: String? = null
    ): ApkSignatureVerificationResult {
        val normalizedFlavor = distributionFlavor.trim().lowercase()
        if (normalizedFlavor == "play") {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.MISMATCH,
                errorCode = "OTA_DISABLED_PLAY_FLAVOR",
                reasonVi = "Phiên bản Google Play không hỗ trợ tự cài đặt tệp APK ngoài."
            )
        }
        if (normalizedFlavor.isNotEmpty() && normalizedFlavor != "github") {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.MISMATCH,
                errorCode = "UNSUPPORTED_CHANNEL",
                reasonVi = "Kênh phân phối ($distributionFlavor) không cho phép cài đặt gói OTA APK."
            )
        }

        if (archivePackageName.isNullOrBlank()) {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.UNREADABLE,
                errorCode = "CERT_UNREADABLE",
                reasonVi = "Không thể đọc thông tin gói hoặc chữ ký số từ tệp APK mới (APP-03)."
            )
        }

        if (archivePackageName != expectedPackageName) {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.MISMATCH,
                errorCode = "CERT_MISMATCH",
                reasonVi = "Tên gói APK ($archivePackageName) không khớp với ứng dụng LifeOS ($expectedPackageName)."
            )
        }

        val installedActive = installedIdentity?.activeCertSha256s
            ?.mapNotNull(::normalizeSha256Hex)
            ?.distinct()
            .orEmpty()
        val archiveActive = archiveIdentity?.activeCertSha256s
            ?.mapNotNull(::normalizeSha256Hex)
            ?.distinct()
            .orEmpty()
        val archiveLineage = archiveIdentity?.lineageCertSha256s
            ?.mapNotNull(::normalizeSha256Hex)
            ?.distinct()
            .orEmpty()

        if (installedIdentity == null || installedActive.isEmpty()) {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.UNREADABLE,
                errorCode = "CERT_UNREADABLE",
                reasonVi = "Không thể đọc chứng chỉ ký số của phiên bản LifeOS đang cài đặt. Đã chặn cài đặt an toàn (APP-03).",
                archiveSignerSha256s = archiveActive
            )
        }

        if (archiveIdentity == null || archiveActive.isEmpty()) {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.UNREADABLE,
                errorCode = "CERT_UNREADABLE",
                reasonVi = "Không thể đọc chứng chỉ ký số từ tệp APK mới. Tệp có thể thiếu chữ ký hoặc bị hỏng (APP-03).",
                installedSignerSha256s = installedActive
            )
        }

        val pinnedChannelCert = normalizeSha256Hex(expectedChannelCertSha256)
        if (pinnedChannelCert != null && !archiveActive.contains(pinnedChannelCert)) {
            return ApkSignatureVerificationResult(
                status = ApkSignatureStatus.MISMATCH,
                errorCode = "CERT_MISMATCH",
                reasonVi = "Chứng chỉ ký của tệp APK không khớp với chứng chỉ tin cậy của kênh phát hành GitHub (APP-03).",
                archiveSignerSha256s = archiveActive,
                installedSignerSha256s = installedActive
            )
        }

        val sameActiveSigners = installedActive.toSet() == archiveActive.toSet()
        val validForwardRotation = !installedIdentity.hasMultipleSigners &&
            !archiveIdentity.hasMultipleSigners &&
            installedActive.size == 1 &&
            archiveActive.size == 1 &&
            archiveLineage.isNotEmpty() &&
            run {
                val installedCert = installedActive.single()
                val archiveCert = archiveActive.single()
                val installedIdx = archiveLineage.indexOf(installedCert)
                val archiveIdx = archiveLineage.indexOf(archiveCert)
                installedIdx >= 0 && archiveIdx >= installedIdx && archiveIdx == archiveLineage.lastIndex
            }

        return if (sameActiveSigners || validForwardRotation) {
            ApkSignatureVerificationResult(
                status = ApkSignatureStatus.MATCH,
                archiveSignerSha256s = archiveActive,
                installedSignerSha256s = installedActive
            )
        } else {
            ApkSignatureVerificationResult(
                status = ApkSignatureStatus.MISMATCH,
                errorCode = "CERT_MISMATCH",
                reasonVi = "Chứng chỉ ký của gói APK mới không khớp với phiên bản đang cài đặt (APP-03).",
                archiveSignerSha256s = archiveActive,
                installedSignerSha256s = installedActive
            )
        }
    }

    fun verifyApk(
        context: Context,
        apkFile: File,
        distributionFlavor: String = BuildConfig.DISTRIBUTION_FLAVOR,
        expectedChannelCertSha256: String? = null
    ): ApkSignatureVerificationResult {
        val pm = context.packageManager
        val pkgName = context.packageName
        return try {
            val archiveInfo = getArchivePackageInfo(pm, apkFile)
                ?: return ApkSignatureVerificationResult(
                    status = ApkSignatureStatus.UNREADABLE,
                    errorCode = "CERT_UNREADABLE",
                    reasonVi = "Tệp APK không hợp lệ, thiếu chữ ký số hoặc bị hỏng (APP-03)."
                )
            val installedIdentity = getInstalledSignerIdentity(pm, pkgName)
            val archiveIdentity = extractSignerIdentity(archiveInfo)
            evaluateVerification(
                expectedPackageName = pkgName,
                archivePackageName = archiveInfo.packageName,
                installedIdentity = installedIdentity,
                archiveIdentity = archiveIdentity,
                distributionFlavor = distributionFlavor,
                expectedChannelCertSha256 = expectedChannelCertSha256
            )
        } catch (e: Exception) {
            ApkSignatureVerificationResult(
                status = ApkSignatureStatus.UNREADABLE,
                errorCode = "CERT_UNREADABLE",
                reasonVi = "Không thể xác minh chữ ký số của tệp APK: ${e.message ?: "lỗi đọc chứng chỉ"}"
            )
        }
    }

    /**
     * Backward-compatible helper returning `null` ONLY on [ApkSignatureStatus.MATCH],
     * or a user-facing Vietnamese rejection reason for `MISMATCH` / `UNREADABLE`.
     */
    fun verifyApkPackageAndSigningCert(context: Context, apkFile: File): String? {
        val outcome = verifyApk(context, apkFile)
        return if (outcome.isMatch) {
            null
        } else {
            outcome.reasonVi ?: "Không thể xác minh chữ ký số của tệp APK (APP-03)."
        }
    }

    private fun getArchivePackageInfo(pm: PackageManager, apkFile: File): PackageInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
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
        }
    }

    private fun getInstalledSignerIdentity(pm: PackageManager, pkgName: String): SignerIdentitySnapshot? {
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
            extractSignerIdentity(info)
        } catch (_: Exception) {
            null
        }
    }

    private fun extractSignerIdentity(pkgInfo: PackageInfo): SignerIdentitySnapshot? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = pkgInfo.signingInfo ?: return null
                val multiple = signingInfo.hasMultipleSigners()
                val activeHashes = signingInfo.apkContentsSigners
                    ?.map { sha256Hex(it.toByteArray()) }
                    .orEmpty()
                if (activeHashes.isEmpty()) return null
                val lineageHashes = if (!multiple) {
                    signingInfo.signingCertificateHistory
                        ?.map { sha256Hex(it.toByteArray()) }
                        .orEmpty()
                } else {
                    emptyList()
                }
                SignerIdentitySnapshot(
                    activeCertSha256s = activeHashes,
                    lineageCertSha256s = lineageHashes,
                    hasMultipleSigners = multiple
                )
            } else {
                @Suppress("DEPRECATION")
                val sigs = pkgInfo.signatures
                val activeHashes = sigs?.map { sha256Hex(it.toByteArray()) }.orEmpty()
                if (activeHashes.isEmpty()) return null
                SignerIdentitySnapshot(
                    activeCertSha256s = activeHashes,
                    lineageCertSha256s = emptyList(),
                    hasMultipleSigners = activeHashes.size > 1
                )
            }
        } catch (_: Exception) {
            null
        }
    }
}
