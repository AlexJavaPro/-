package ru.amajo.photomailer.picker

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class SafPhotoPicker(
    private val activity: FlutterFragmentActivity,
) {
    private enum class Source {
        AUTO,
        GALLERY,
        FILES,
    }

    private var pendingResult: MethodChannel.Result? = null
    private val galleryPickLimit = resolveGalleryPickLimit()

    private val galleryPickerLauncher = activity.registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(galleryPickLimit),
    ) { uris ->
        completeWithUris(uris)
    }

    private val documentsPickerLauncher = activity.registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        completeWithUris(uris)
    }

    fun pick(
        result: MethodChannel.Result,
        sourceRaw: String? = null,
    ) {
        if (pendingResult != null) {
            result.error("picker_busy", "Picker already active", null)
            return
        }
        pendingResult = result
        when (parseSource(sourceRaw)) {
            Source.AUTO -> launchGalleryPicker(fallbackToDocuments = true)
            Source.GALLERY -> launchGalleryPicker(fallbackToDocuments = false)
            Source.FILES -> launchDocumentsPicker()
        }
    }

    private fun parseSource(raw: String?): Source {
        return when (raw?.trim()?.lowercase()) {
            "gallery" -> Source.GALLERY
            "files" -> Source.FILES
            else -> Source.AUTO
        }
    }

    private fun launchGalleryPicker(fallbackToDocuments: Boolean) {
        runCatching {
            galleryPickerLauncher.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
            )
        }.onFailure { error ->
            if (fallbackToDocuments) {
                launchDocumentsPicker()
                return@onFailure
            }
            val result = pendingResult
            pendingResult = null
            result?.error(
                "picker_launch_failed",
                "Не удалось открыть галерею. Повторите попытку.",
                error.message,
            )
        }
    }

    private fun launchDocumentsPicker() {
        runCatching {
            documentsPickerLauncher.launch(arrayOf("image/*"))
        }.onFailure { error ->
            val result = pendingResult
            pendingResult = null
            result?.error(
                "picker_launch_failed",
                "Не удалось открыть выбор файлов. Повторите попытку.",
                error.message,
            )
        }
    }

    private fun completeWithUris(uris: List<Uri>) {
        val result = pendingResult ?: return
        pendingResult = null

        runCatching {
            uris.map { uri ->
                tryPersistReadPermission(uri)
                val metadata = readMetadata(uri)
                mapOf(
                    "uri" to uri.toString(),
                    "name" to metadata.name,
                    "sizeBytes" to metadata.sizeBytes,
                    "mimeType" to activity.contentResolver.getType(uri),
                    "capturedAtMillis" to metadata.capturedAtMillis,
                    "thumbnailBytes" to createThumbnail(uri),
                )
            }
        }.onSuccess(result::success)
            .onFailure { error ->
                result.error("picker_failed", error.message, null)
            }
    }

    private fun tryPersistReadPermission(uri: Uri) {
        runCatching {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
    }

    private fun readMetadata(uri: Uri): FileMetadata {
        var name = "photo_${System.currentTimeMillis()}"
        var size = 0L
        var timestamp: Long? = null
        activity.contentResolver.query(
            uri,
            arrayOf(
                OpenableColumns.DISPLAY_NAME,
                OpenableColumns.SIZE,
                MediaStore.Images.ImageColumns.DATE_TAKEN,
                MediaStore.MediaColumns.DATE_ADDED,
                MediaStore.MediaColumns.DATE_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    name = cursor.getString(nameIndex) ?: name
                }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0) {
                    size = cursor.getLong(sizeIndex).coerceAtLeast(0L)
                }

                val dateTaken = readMillis(cursor, MediaStore.Images.ImageColumns.DATE_TAKEN)
                val dateAdded = readMillis(cursor, MediaStore.MediaColumns.DATE_ADDED)
                val dateModified = readMillis(cursor, MediaStore.MediaColumns.DATE_MODIFIED)
                timestamp = dateTaken ?: dateAdded ?: dateModified ?: timestamp
            }
        }
        return FileMetadata(name = name, sizeBytes = size, capturedAtMillis = timestamp)
    }

    private fun readMillis(cursor: android.database.Cursor, columnName: String): Long? {
        val index = cursor.getColumnIndex(columnName)
        if (index < 0) {
            return null
        }
        val raw = cursor.getLong(index)
        if (raw <= 0L) {
            return null
        }
        return if (raw < 1_000_000_000_000L) raw * 1000L else raw
    }

    private data class FileMetadata(
        val name: String,
        val sizeBytes: Long,
        val capturedAtMillis: Long?,
    )

    private fun createThumbnail(uri: Uri): ByteArray? {
        return runCatching {
            val bounds = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            activity.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, bounds)
            }

            val sampleSize = calculateSampleSize(
                width = bounds.outWidth,
                height = bounds.outHeight,
                maxSize = THUMBNAIL_EDGE_PX,
            )

            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val bitmap = activity.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
            } ?: return@runCatching null

            try {
                ByteArrayOutputStream().use { output ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_QUALITY, output)
                    output.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        }.getOrNull()
    }

    private fun calculateSampleSize(
        width: Int,
        height: Int,
        maxSize: Int,
    ): Int {
        if (width <= 0 || height <= 0) {
            return 1
        }
        var sampleSize = 1
        var currentWidth = width
        var currentHeight = height
        while (currentWidth > maxSize || currentHeight > maxSize) {
            currentWidth /= 2
            currentHeight /= 2
            sampleSize *= 2
        }
        return sampleSize.coerceAtLeast(1)
    }

    companion object {
        private const val LEGACY_GALLERY_LIMIT = 50
        private const val THUMBNAIL_EDGE_PX = 220
        private const val THUMBNAIL_QUALITY = 82
    }

    private fun resolveGalleryPickLimit(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return MediaStore.getPickImagesMaxLimit().coerceAtLeast(1)
        }
        return LEGACY_GALLERY_LIMIT
    }
}
