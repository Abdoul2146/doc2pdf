package com.magnatrus.doc2pdf

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import java.io.File
import java.io.IOException

/**
 * Publishes a finished PDF into the shared `Documents/doc2pdf` folder, so every
 * app and file manager on the device can see it (the app's own documents
 * directory is private and appears nowhere in the system UI).
 *
 * API 29+ publishes through [MediaStore] (scoped storage, no permission).
 * API 26-28 writes straight into the public Documents directory, which requires
 * `WRITE_EXTERNAL_STORAGE`.
 *
 * Never throws: a failure is reported through [Published.failure] so the
 * conversion itself can still succeed.
 */
class DocumentPublisher(private val context: Context) {

    companion object {
        const val FOLDER_NAME = "doc2pdf"
        const val RELATIVE_LOCATION = "Documents/$FOLDER_NAME"
        private const val MIME_PDF = "application/pdf"
    }

    data class Published(
        /** Human-readable folder, e.g. `Documents/doc2pdf`. */
        val location: String? = null,
        /** Final file name, which may differ if a file of that name already existed. */
        val displayName: String? = null,
        /** Absolute path, only known on API 26-28. */
        val path: String? = null,
        /** Set when publishing failed; the conversion is still considered successful. */
        val failure: String? = null,
    )

    fun publish(source: File, requestedName: String): Published =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(source, requestedName)
        } else {
            publishLegacy(source, requestedName)
        }

    // ------------------------------------------------------------- API 29+

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun publishViaMediaStore(source: File, requestedName: String): Published {
        val resolver = context.contentResolver
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, requestedName)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME_PDF)
            put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_LOCATION)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri: Uri? = try {
            resolver.insert(collection, values)
        } catch (t: Throwable) {
            null
        }
        if (uri == null) {
            return Published(failure = "Could not create a file in $RELATIVE_LOCATION")
        }

        return try {
            resolver.openOutputStream(uri, "w").use { out ->
                if (out == null) throw IOException("MediaStore returned no output stream")
                source.inputStream().use { input -> input.copyTo(out) }
            }
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
            Published(
                location = RELATIVE_LOCATION,
                displayName = queryDisplayName(uri) ?: requestedName,
            )
        } catch (t: Throwable) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Throwable) {
                // Best effort cleanup only.
            }
            Published(failure = "Could not write the PDF into $RELATIVE_LOCATION")
        }
    }

    /** MediaStore de-duplicates names, so read back the name it actually used. */
    private fun queryDisplayName(uri: Uri): String? = try {
        context.contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (t: Throwable) {
        null
    }

    // --------------------------------------------------------- API 26-28

    @Suppress("DEPRECATION")
    private fun publishLegacy(source: File, requestedName: String): Published {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            return Published(
                failure = "Allow storage access to save the PDF into $RELATIVE_LOCATION",
            )
        }

        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
            FOLDER_NAME,
        )
        if (!dir.exists() && !dir.mkdirs()) {
            return Published(failure = "Could not create $RELATIVE_LOCATION")
        }

        val target = uniqueFile(dir, requestedName)
        return try {
            source.inputStream().use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            MediaScannerConnection.scanFile(
                context,
                arrayOf(target.absolutePath),
                arrayOf(MIME_PDF),
                null,
            )
            Published(
                location = RELATIVE_LOCATION,
                displayName = target.name,
                path = target.absolutePath,
            )
        } catch (t: Throwable) {
            Published(failure = "Could not write the PDF into $RELATIVE_LOCATION")
        }
    }

    private fun uniqueFile(dir: File, name: String): File {
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var candidate = File(dir, name)
        var index = 1
        while (candidate.exists()) {
            candidate = File(dir, "$stem ($index)$extension")
            index++
        }
        return candidate
    }
}
