package vn.lifeos.app.life_os

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LifeOsApkSignatureVerifierTest {

    private val pkg = "vn.lifeos.app.life_os"
    private val certA = "a".repeat(64)
    private val certB = "b".repeat(64)
    private val certC = "c".repeat(64)

    @Test
    fun evaluateVerification_returnsMatch_whenSameSingleSignerOnGithubChannel() {
        val result = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            distributionFlavor = "github"
        )

        assertEquals(ApkSignatureStatus.MATCH, result.status)
        assertTrue(result.isMatch)
    }

    @Test
    fun evaluateVerification_returnsMatch_forValidForwardKeyRotationLineage() {
        val result = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(
                activeCertSha256s = listOf(certA),
                lineageCertSha256s = listOf(certA)
            ),
            archiveIdentity = SignerIdentitySnapshot(
                activeCertSha256s = listOf(certB),
                lineageCertSha256s = listOf(certA, certB)
            ),
            distributionFlavor = "github"
        )

        assertEquals(ApkSignatureStatus.MATCH, result.status)
        assertTrue(result.isMatch)
    }

    @Test
    fun evaluateVerification_returnsMismatch_whenCertDiffersWithoutLineage() {
        val result = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certB)),
            distributionFlavor = "github"
        )

        assertEquals(ApkSignatureStatus.MISMATCH, result.status)
        assertFalse(result.isMatch)
        assertEquals("CERT_MISMATCH", result.errorCode)
        assertNotNull(result.reasonVi)
    }

    @Test
    fun evaluateVerification_returnsMismatch_onRollbackToOlderLineageCertOrUntrustedLineage() {
        // Installed is already certB; archive claims only certA
        val rollback = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(
                activeCertSha256s = listOf(certB),
                lineageCertSha256s = listOf(certA, certB)
            ),
            archiveIdentity = SignerIdentitySnapshot(
                activeCertSha256s = listOf(certA),
                lineageCertSha256s = listOf(certA)
            ),
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.MISMATCH, rollback.status)

        // Archive lineage doesn't contain installed certA
        val unrelatedLineage = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(
                activeCertSha256s = listOf(certB),
                lineageCertSha256s = listOf(certC, certB)
            ),
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.MISMATCH, unrelatedLineage.status)
    }

    @Test
    fun evaluateVerification_returnsMismatch_onPackageMismatchOrPlayFlavor() {
        val wrongPkg = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = "com.evil.clone",
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.MISMATCH, wrongPkg.status)

        val playFlavor = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            distributionFlavor = "play"
        )
        assertEquals(ApkSignatureStatus.MISMATCH, playFlavor.status)
        assertEquals("OTA_DISABLED_PLAY_FLAVOR", playFlavor.errorCode)
    }

    @Test
    fun evaluateVerification_returnsUnreadable_whenInstalledOrArchiveCertIsMissingOrInvalid() {
        val missingInstalled = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = null,
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.UNREADABLE, missingInstalled.status)
        assertFalse(missingInstalled.isMatch)
        assertEquals("CERT_UNREADABLE", missingInstalled.errorCode)
        assertNotNull(missingInstalled.reasonVi)

        val missingArchive = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = null,
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.UNREADABLE, missingArchive.status)
        assertFalse(missingArchive.isMatch)
        assertEquals("CERT_UNREADABLE", missingArchive.errorCode)
        assertNotNull(missingArchive.reasonVi)

        val emptyArchiveCerts = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = pkg,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf("invalid_hex")),
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.UNREADABLE, emptyArchiveCerts.status)
        assertFalse(emptyArchiveCerts.isMatch)

        val missingPackageName = LifeOsApkSignatureVerifier.evaluateVerification(
            expectedPackageName = pkg,
            archivePackageName = null,
            installedIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            archiveIdentity = SignerIdentitySnapshot(activeCertSha256s = listOf(certA)),
            distributionFlavor = "github"
        )
        assertEquals(ApkSignatureStatus.UNREADABLE, missingPackageName.status)
    }
}
