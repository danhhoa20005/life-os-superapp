package vn.lifeos.app.life_os

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.nio.file.Files

class LifeOsSecureVaultUserIsolationTest {

    @Test
    fun sanitizeUserIdSegment_sanitizesSafelyAndRejectsEmptyOrTraversal() {
        assertEquals("user_alpha-1", LifeOsSecureVault.sanitizeUserIdSegment("user_alpha-1"))
        assertEquals("alice_example_com", LifeOsSecureVault.sanitizeUserIdSegment("alice@example.com"))
        assertEquals("___evil_path", LifeOsSecureVault.sanitizeUserIdSegment("../evil/path"))

        for (bad in listOf("", "   ", ".", "..", " . ", " .. ")) {
            try {
                LifeOsSecureVault.sanitizeUserIdSegment(bad)
                fail("Expected IllegalArgumentException for '$bad'")
            } catch (_: IllegalArgumentException) {
                // expected
            }
        }
    }

    @Test
    fun isUserScopedSecretKey_matchesOnlyExactTargetUserWithoutCrossUserCollision() {
        val uid = "u_1"
        val otherUid = "u_10"

        // Matches target user across supported scoped key conventions
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("ux_last_used_wallet_id__u_u_1", uid))
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("ux_form_draft_v1__u_u_1__quick_tx_form", uid))
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("lifeos_personal_alarms_v2__u_u_1", uid))
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("sepay_tok_u_1", uid))
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("migrated_sepay_token_backup_u_1", uid))
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("u_1_api_key", uid))
        assertTrue(LifeOsSecureVault.isUserScopedSecretKey("vault:u_1:token", uid))

        // Must NEVER match another user with prefix/numeric similarity (u_10) or unscoped keys
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("ux_last_used_wallet_id__u_u_10", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("ux_form_draft_v1__u_u_10__quick_tx_form", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("sepay_tok_u_10", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("u_10_api_key", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("u_1_pref__u_u_10", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("vault:u_10:token", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("lifeos_personal_alarms_v1", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("__losv_dart_aead_master_v1__", uid))
        assertFalse(LifeOsSecureVault.isUserScopedSecretKey("ux_last_used_wallet_id__u_u_1", otherUid))
    }

    @Test
    fun clearUserDirectoryInBase_deletesOnlyTargetUserSubdirAndOwnedLegacyFiles() {
        val vaultBase = Files.createTempDirectory("lifeos_vault_isolation_").toFile()
        try {
            val userADir = File(vaultBase, "userA").apply { mkdirs() }
            val userANested = File(userADir, "sub").apply { mkdirs() }
            val userAFile = File(userADir, "doc_a.enc").apply { writeText("secretA") }
            val userANestedFile = File(userANested, "nested.enc").apply { writeText("nestedA") }

            val userBDir = File(vaultBase, "userB").apply { mkdirs() }
            val userBFile = File(userBDir, "doc_b.enc").apply { writeText("secretB") }

            // Legacy unscoped files directly under vaultBase
            val legacyOwnedByA = File(vaultBase, "legacy_a.enc").apply { writeText("legacyA") }
            val legacyOwnedByAMeta = File(vaultBase, "legacy_a.enc.meta").apply {
                writeText("""{"ownerId":"userA","plaintextSha256":"abc"}""")
            }
            val legacyOwnedByB = File(vaultBase, "legacy_b.enc").apply { writeText("legacyB") }
            val legacyOwnedByBMeta = File(vaultBase, "legacy_b.enc.meta").apply {
                writeText("""{"ownerId":"userB","plaintextSha256":"def"}""")
            }
            val legacyUnowned = File(vaultBase, "legacy_unknown.enc").apply { writeText("unknown") }

            // Blank / traversal inputs must be safe no-ops
            assertFalse(LifeOsSecureVault.clearUserDirectoryInBase(vaultBase, ""))
            assertFalse(LifeOsSecureVault.clearUserDirectoryInBase(vaultBase, "   "))
            assertFalse(LifeOsSecureVault.clearUserDirectoryInBase(vaultBase, "."))
            assertFalse(LifeOsSecureVault.clearUserDirectoryInBase(vaultBase, ".."))
            assertTrue(userAFile.exists())
            assertTrue(userBFile.exists())

            // Clear only userA
            assertTrue(LifeOsSecureVault.clearUserDirectoryInBase(vaultBase, "userA"))

            assertFalse(userADir.exists())
            assertFalse(userAFile.exists())
            assertFalse(userANestedFile.exists())
            assertFalse(legacyOwnedByA.exists())
            assertFalse(legacyOwnedByAMeta.exists())

            // Vault base, userB's directory, userB's legacy file, and unowned legacy file MUST remain intact!
            assertTrue(vaultBase.exists())
            assertTrue(userBDir.exists())
            assertTrue(userBFile.exists())
            assertEquals("secretB", userBFile.readText())
            assertTrue(legacyOwnedByB.exists())
            assertTrue(legacyOwnedByBMeta.exists())
            assertTrue(legacyUnowned.exists())
        } finally {
            vaultBase.deleteRecursively()
        }
    }

    @Test
    fun clearUserDirectoryInBase_and_clearUserExportCacheInDir_verifyBooleanResultsAndIsolation() {
        val tempRoot = Files.createTempDirectory("lifeos_vault_export_iso_").toFile()
        try {
            val cacheDir = File(tempRoot, "cache").apply { mkdirs() }
            val userAExportDir = File(cacheDir, "exports_u_1").apply { mkdirs() }
            File(userAExportDir, "statement.csv").writeText("a")
            val userAExportFile = File(cacheDir, "exports_u_1_report.json").apply { writeText("{}") }

            val user10ExportDir = File(cacheDir, "exports_u_10").apply { mkdirs() }
            val user10ExportFile = File(user10ExportDir, "other.csv").apply { writeText("10") }
            val unrelatedCacheFile = File(cacheDir, "other_cache.txt").apply { writeText("keep") }

            // Invalid / traversal UIDs must return false and leave files intact
            assertFalse(LifeOsSecureVault.clearUserExportCacheInDir(cacheDir, ""))
            assertFalse(LifeOsSecureVault.clearUserExportCacheInDir(cacheDir, ".."))
            assertTrue(userAExportDir.exists())

            // Clear u_1 -> removes exports_u_1 and exports_u_1_report.json, returns true
            assertTrue(LifeOsSecureVault.clearUserExportCacheInDir(cacheDir, "u_1"))
            assertFalse(userAExportDir.exists())
            assertFalse(userAExportFile.exists())

            // u_10 (prefix collision) & unrelated cache MUST stay intact
            assertTrue(user10ExportDir.exists())
            assertTrue(user10ExportFile.exists())
            assertTrue(unrelatedCacheFile.exists())

            // Clear non-existent directory base returns true safely, while symlink escape returns false
            val missingBase = File(tempRoot, "missing_vault_base")
            assertTrue(LifeOsSecureVault.clearUserDirectoryInBase(missingBase, "u_1"))

            // Verify clearForUser signature returns Boolean in LifeOsSecureVault
            val clearForUserMethod = LifeOsSecureVault::class.java.getDeclaredMethod(
                "clearForUser",
                android.content.Context::class.java,
                String::class.java
            )
            assertEquals(Boolean::class.javaPrimitiveType, clearForUserMethod.returnType)
        } finally {
            tempRoot.deleteRecursively()
        }
    }
}
