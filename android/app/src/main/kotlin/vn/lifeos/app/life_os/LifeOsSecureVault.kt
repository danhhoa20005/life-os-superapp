package vn.lifeos.app.life_os

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hardware-backed Android Keystore AES-256-GCM encrypted secret & document vault.
 * Protects sensitive credentials (such as SePay API tokens) and local attachments
 * on device so raw secrets and document binaries are NEVER written to Cloud Firestore
 * or stored as plaintext on disk.
 */
object LifeOsSecureVault {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "vn.lifeos.app.hardware_vault_key_v1"
    private const val PREFS_NAME = "lifeos_hardware_vault_prefs_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val GCM_TAG_BYTES = 16
    private const val GCM_IV_BYTES = 12
    private const val PACKET_VERSION: Byte = 1
    private val MAGIC_HEADER = byteArrayOf('L'.code.toByte(), 'O'.code.toByte(), 'S'.code.toByte(), 'V'.code.toByte())
    private const val VAULT_DIR_NAME = "secure_doc_vault"
    private const val RECEIPT_CACHE_DIR_NAME = "receipt_captures"

    @Synchronized
    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = try {
            keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        } catch (_: Exception) {
            null
        }
        if (existing != null) {
            return existing.secretKey
        }
        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        keyGen.init(spec)
        return keyGen.generateKey()
    }

    @Synchronized
    private fun resetInvalidatedKey() {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
            }
        } catch (_: Exception) {
        }
    }

    private fun initEncryptCipherWithRecovery(): Cipher {
        return try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            resetInvalidatedKey()
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
            }
        } catch (e: UnrecoverableKeyException) {
            resetInvalidatedKey()
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
            }
        }
    }

    fun writeSecret(context: Context, key: String, plaintext: String) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (plaintext.isBlank()) {
            prefs.edit().remove(key).apply()
            return
        }
        val cipher = initEncryptCipherWithRecovery()
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val ivB64 = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val cipherBytes = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val ctB64 = Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
        prefs.edit().putString(key, "$ivB64:$ctB64").apply()
    }

    fun readSecret(context: Context, key: String): String? {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(key, null) ?: return null
        val parts = stored.split(":", limit = 2)
        if (parts.size != 2) return null
        val iv = try {
            Base64.decode(parts[0], Base64.NO_WRAP)
        } catch (_: Exception) {
            return null
        }
        val ct = try {
            Base64.decode(parts[1], Base64.NO_WRAP)
        } catch (_: Exception) {
            return null
        }

        // 1. Primary path: decrypt with GCM AAD bound to `key`
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
            return String(cipher.doFinal(ct), Charsets.UTF_8)
        } catch (e: KeyPermanentlyInvalidatedException) {
            resetInvalidatedKey()
            prefs.edit().remove(key).apply()
            return null
        } catch (e: UnrecoverableKeyException) {
            resetInvalidatedKey()
            prefs.edit().remove(key).apply()
            return null
        } catch (_: AEADBadTagException) {
            // Fall through to legacy un-AAD secret check
        } catch (_: Exception) {
            return null
        }

        // 2. Backward-compatible fallback for legacy secrets written without AAD
        return try {
            val legacyCipher = Cipher.getInstance(TRANSFORMATION)
            legacyCipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateSecretKey(),
                GCMParameterSpec(GCM_TAG_BITS, iv)
            )
            val plain = String(legacyCipher.doFinal(ct), Charsets.UTF_8)
            // Upgrade legacy entry in-place to AAD-bound format
            try {
                writeSecret(context, key, plain)
            } catch (_: Exception) {
            }
            plain
        } catch (e: KeyPermanentlyInvalidatedException) {
            resetInvalidatedKey()
            prefs.edit().remove(key).apply()
            null
        } catch (_: Exception) {
            null
        }
    }

    fun deleteSecret(context: Context, key: String) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove(key).apply()
    }

    fun getVaultDirectory(context: Context): File {
        val dir = File(context.applicationContext.noBackupFilesDir, VAULT_DIR_NAME)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    fun getLegacyVaultDirectory(context: Context): File {
        return File(context.applicationContext.filesDir, VAULT_DIR_NAME)
    }

    /**
     * Encrypts arbitrary binary payloads using hardware-backed AES-256-GCM.
     * Binary envelope: magic "LOSV" (4B) + ver=1 (1B) + ivLen=12 (1B) + iv (12B) + ciphertextWithTag.
     */
    fun encryptBytes(context: Context, plainBytes: ByteArray, aadString: String = ""): ByteArray {
        val cipher = initEncryptCipherWithRecovery()
        if (aadString.isNotEmpty()) {
            cipher.updateAAD(aadString.toByteArray(Charsets.UTF_8))
        }
        val iv = cipher.iv
        require(iv.size == GCM_IV_BYTES) { "Unexpected GCM IV length: ${iv.size}" }
        val cipherWithTag = cipher.doFinal(plainBytes)

        val out = ByteArray(MAGIC_HEADER.size + 2 + iv.size + cipherWithTag.size)
        System.arraycopy(MAGIC_HEADER, 0, out, 0, MAGIC_HEADER.size)
        out[4] = PACKET_VERSION
        out[5] = iv.size.toByte()
        System.arraycopy(iv, 0, out, 6, iv.size)
        System.arraycopy(cipherWithTag, 0, out, 6 + iv.size, cipherWithTag.size)
        return out
    }

    /**
     * Decrypts a binary envelope created by [encryptBytes], verifying magic, version,
     * GCM authentication tag, and [aadString]. Fails closed on any mismatch.
     */
    fun decryptBytes(context: Context, cipherPack: ByteArray, aadString: String = ""): ByteArray {
        val minPacketBytes = MAGIC_HEADER.size + 2 + GCM_IV_BYTES + GCM_TAG_BYTES
        require(cipherPack.size >= minPacketBytes) {
            "Corrupted or truncated vault packet (${cipherPack.size} bytes)."
        }
        for (i in MAGIC_HEADER.indices) {
            require(cipherPack[i] == MAGIC_HEADER[i]) {
                "Invalid vault packet header."
            }
        }
        val version = cipherPack[4]
        require(version == PACKET_VERSION) { "Unsupported vault packet version: $version" }
        val ivLen = cipherPack[5].toInt() and 0xFF
        require(ivLen == GCM_IV_BYTES && cipherPack.size >= 6 + ivLen + GCM_TAG_BYTES) {
            "Invalid vault IV length: $ivLen"
        }
        val iv = cipherPack.copyOfRange(6, 6 + ivLen)
        val cipherWithTag = cipherPack.copyOfRange(6 + ivLen, cipherPack.size)

        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            if (aadString.isNotEmpty()) {
                cipher.updateAAD(aadString.toByteArray(Charsets.UTF_8))
            }
            cipher.doFinal(cipherWithTag)
        } catch (e: KeyPermanentlyInvalidatedException) {
            resetInvalidatedKey()
            throw IllegalStateException("Hardware vault key was invalidated by OS security policy.", e)
        } catch (e: UnrecoverableKeyException) {
            resetInvalidatedKey()
            throw IllegalStateException("Hardware vault key is no longer recoverable.", e)
        }
    }

    fun clearAll(context: Context) {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
        val vaultDir = File(appCtx.noBackupFilesDir, VAULT_DIR_NAME)
        if (vaultDir.exists()) vaultDir.deleteRecursively()
        val legacyDir = File(appCtx.filesDir, VAULT_DIR_NAME)
        if (legacyDir.exists()) legacyDir.deleteRecursively()

        // Purge ephemeral receipt captures and exported CSV/JSON statement caches
        try {
            val receiptCacheDir = File(appCtx.cacheDir, RECEIPT_CACHE_DIR_NAME)
            if (receiptCacheDir.exists()) {
                receiptCacheDir.deleteRecursively()
            }
            appCtx.cacheDir.listFiles()?.forEach { file ->
                if (file.isFile) {
                    val lower = file.name.lowercase()
                    if (lower.endsWith(".csv") || lower.endsWith(".json")) {
                        file.delete()
                    }
                }
            }
        } catch (_: Exception) {
        }
    }
}
