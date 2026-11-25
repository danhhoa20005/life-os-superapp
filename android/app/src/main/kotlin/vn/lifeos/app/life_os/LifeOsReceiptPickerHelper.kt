package vn.lifeos.app.life_os

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import java.io.File

/**
 * Native Receipt Image Picker & Camera Capture helper (Section 19).
 * Copies selected gallery or camera receipt images into ephemeral app cache
 * (`cacheDir/receipt_captures/`) without requiring broad external storage permissions.
 */
object LifeOsReceiptPickerHelper {
    const val REQ_PICK_GALLERY = 7211
    const val REQ_CAPTURE_CAMERA = 7212

    fun launchGalleryPicker(activity: Activity): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent.createChooser(intent, "Chọn ảnh hóa đơn"),
                REQ_PICK_GALLERY
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    fun launchCameraCapture(activity: Activity): File? {
        return try {
            val dir = File(activity.cacheDir, "receipt_captures")
            if (!dir.exists()) dir.mkdirs()
            val outFile = File(dir, "receipt_${System.currentTimeMillis()}.jpg")
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                outFile
            )
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQ_CAPTURE_CAMERA)
            outFile
        } catch (_: Exception) {
            null
        }
    }

    fun copyUriToReceiptCache(context: Context, uri: Uri): Map<String, Any>? {
        return try {
            val dir = File(context.cacheDir, "receipt_captures")
            if (!dir.exists()) dir.mkdirs()
            val displayName = resolveDisplayName(context, uri) ?: "receipt_${System.currentTimeMillis()}.jpg"
            val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val dest = File(dir, "${System.currentTimeMillis()}_$safeName")
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            if (!dest.exists() || dest.length() <= 0L) return null
            mapOf(
                "filePath" to dest.absolutePath,
                "fileName" to safeName,
                "sizeBytes" to dest.length()
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveDisplayName(context: Context, uri: Uri): String? {
        return try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) cursor.getString(idx) else null
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }
}
