package ru.amajo.photomailer.files

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max
import ru.amajo.photomailer.db.PhotoEntity
import ru.amajo.photomailer.mail.MimeResolver

data class PreparedAttachment(
    val file: File,
    val displayName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val wasCompressed: Boolean,
    val exceedsLimit: Boolean,
)

class AttachmentPreparer(
    private val context: Context,
    private val mimeResolver: MimeResolver,
    compressionPreset: String = "none",
    private val maxAttachmentBytes: Long = Long.MAX_VALUE,
    private val compressionMode: CompressionMode = CompressionMode.OVERSIZED_ONLY,
) {
    private val compressionProfile = CompressionProfile.fromPreset(compressionPreset)
    private val tempDir: File by lazy {
        File(context.cacheDir, TEMP_DIR_NAME).apply {
            if (!exists()) {
                mkdirs()
            }
        }
    }

    enum class CompressionMode {
        DISABLED,
        OVERSIZED_ONLY,
        ALWAYS,
    }

    suspend fun copyBatch(photos: List<PhotoEntity>): List<PreparedAttachment> {
        return withContext(Dispatchers.IO) {
            val copied = mutableListOf<PreparedAttachment>()
            try {
                for (photo in photos) {
                    copied += copyOne(photo)
                }
                copied
            } catch (error: Throwable) {
                cleanup(copied)
                throw error
            }
        }
    }

    fun cleanup(attachments: List<PreparedAttachment>) {
        attachments.forEach { attachment ->
            runCatching { attachment.file.delete() }
        }
    }

    private fun copyOne(photo: PhotoEntity): PreparedAttachment {
        val uri = Uri.parse(photo.uri)
        val sourceMimeType = mimeResolver.resolve(photo)
        val extension = photo.name.substringAfterLast('.', "").trim().lowercase()
        val sourceSuffix = if (extension.isBlank()) ".bin" else ".${extension}"
        val sourceSizeBytes = photo.sizeBytes.coerceAtLeast(0L)

        val shouldTryCompression = sourceMimeType.startsWith("image/") && when (compressionMode) {
            CompressionMode.DISABLED -> false
            CompressionMode.ALWAYS -> true
            CompressionMode.OVERSIZED_ONLY -> {
                maxAttachmentBytes > 0L && (sourceSizeBytes <= 0L || sourceSizeBytes > maxAttachmentBytes)
            }
        }

        val prepared: PreparedAttachment = if (shouldTryCompression) {
            val compressedFile = createTempFile(compressionProfile.fileExtension)
            val compressed = compressImageToLimit(
                uri = uri,
                destination = compressedFile,
                maxBytes = maxAttachmentBytes,
            )
            if (compressed.success) {
                val compressedSize = compressedFile.length().coerceAtLeast(0L)
                PreparedAttachment(
                    file = compressedFile,
                    displayName = ensureCompressedFileName(photo.name, compressionProfile.fileExtension),
                    mimeType = compressionProfile.mimeType,
                    sizeBytes = compressedSize,
                    wasCompressed = true,
                    exceedsLimit = maxAttachmentBytes > 0L && compressedSize > maxAttachmentBytes,
                )
            } else {
                runCatching { compressedFile.delete() }
                val fallback = createTempFile(sourceSuffix)
                copyRaw(uri = uri, destination = fallback)
                val copiedSize = fallback.length().coerceAtLeast(0L)
                PreparedAttachment(
                    file = fallback,
                    displayName = photo.name,
                    mimeType = sourceMimeType,
                    sizeBytes = if (copiedSize > 0L) copiedSize else sourceSizeBytes,
                    wasCompressed = false,
                    exceedsLimit = maxAttachmentBytes > 0L && copiedSize > maxAttachmentBytes,
                )
            }
        } else {
            val copied = createTempFile(sourceSuffix)
            copyRaw(uri = uri, destination = copied)
            val copiedSize = copied.length().coerceAtLeast(0L)
            PreparedAttachment(
                file = copied,
                displayName = photo.name,
                mimeType = sourceMimeType,
                sizeBytes = if (copiedSize > 0L) copiedSize else sourceSizeBytes,
                wasCompressed = false,
                exceedsLimit = maxAttachmentBytes > 0L && copiedSize > maxAttachmentBytes,
            )
        }

        return prepared
    }

    private fun copyRaw(uri: Uri, destination: File) {
        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) {
                        break
                    }
                    output.write(buffer, 0, read)
                }
                output.flush()
            }
        } ?: throw IOException("Cannot read $uri")
    }

    private data class CompressionOutcome(
        val success: Boolean,
    )

    private data class CompressionAttempt(
        val jpegQuality: Int,
        val maxImageSidePx: Int,
    )

    private fun compressionAttempts(): List<CompressionAttempt> {
        val base = CompressionAttempt(
            jpegQuality = compressionProfile.quality,
            maxImageSidePx = compressionProfile.maxImageSidePx,
        )
        return listOf(
            base,
            CompressionAttempt(
                jpegQuality = (base.jpegQuality - 10).coerceAtLeast(42),
                maxImageSidePx = (base.maxImageSidePx - 320).coerceAtLeast(1280),
            ),
            CompressionAttempt(
                jpegQuality = (base.jpegQuality - 18).coerceAtLeast(38),
                maxImageSidePx = (base.maxImageSidePx - 640).coerceAtLeast(1024),
            ),
            CompressionAttempt(
                jpegQuality = (base.jpegQuality - 25).coerceAtLeast(34),
                maxImageSidePx = (base.maxImageSidePx - 920).coerceAtLeast(900),
            ),
            CompressionAttempt(
                jpegQuality = (base.jpegQuality - 32).coerceAtLeast(30),
                maxImageSidePx = (base.maxImageSidePx - 1120).coerceAtLeast(768),
            ),
        ).distinctBy { "${it.jpegQuality}:${it.maxImageSidePx}" }
    }

    private fun compressImageToLimit(
        uri: Uri,
        destination: File,
        maxBytes: Long,
    ): CompressionOutcome {
        return runCatching {
            val boundsOptions = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, boundsOptions)
            }
            if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) {
                return CompressionOutcome(success = false)
            }

            var bestAttemptBytes: ByteArray? = null

            for (attempt in compressionAttempts()) {
                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = calculateSampleSize(
                        width = boundsOptions.outWidth,
                        height = boundsOptions.outHeight,
                        maxSide = attempt.maxImageSidePx,
                    )
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }

                val decoded = context.contentResolver.openInputStream(uri)?.use { stream ->
                    BitmapFactory.decodeStream(stream, null, decodeOptions)
                } ?: continue

                val scaled = scaleDownIfNeeded(
                    source = decoded,
                    maxSide = attempt.maxImageSidePx,
                )
                val encoded = try {
                    ByteArrayOutputStream().use { output ->
                        val written = scaled.compress(
                            compressionProfile.format,
                            attempt.jpegQuality,
                            output,
                        )
                        if (!written) {
                            null
                        } else {
                            output.toByteArray()
                        }
                    }
                } finally {
                    if (scaled !== decoded) {
                        scaled.recycle()
                    }
                    decoded.recycle()
                }

                if (encoded == null || encoded.isEmpty()) {
                    continue
                }
                if (bestAttemptBytes == null || encoded.size < bestAttemptBytes!!.size) {
                    bestAttemptBytes = encoded
                }

                if (maxBytes <= 0L || encoded.size.toLong() <= maxBytes) {
                    FileOutputStream(destination).use { output ->
                        output.write(encoded)
                        output.flush()
                    }
                    return CompressionOutcome(success = destination.length() > 0L)
                }
            }

            if (bestAttemptBytes != null) {
                FileOutputStream(destination).use { output ->
                    output.write(bestAttemptBytes)
                    output.flush()
                }
                return CompressionOutcome(success = destination.length() > 0L)
            }

            CompressionOutcome(success = false)
        }.getOrElse {
            CompressionOutcome(success = false)
        }
    }

    private fun scaleDownIfNeeded(source: Bitmap, maxSide: Int): Bitmap {
        val currentMaxSide = max(source.width, source.height)
        if (currentMaxSide <= maxSide) {
            return source
        }
        val ratio = maxSide.toFloat() / currentMaxSide.toFloat()
        val targetWidth = (source.width * ratio).toInt().coerceAtLeast(1)
        val targetHeight = (source.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, targetWidth, targetHeight, true)
    }

    private fun calculateSampleSize(
        width: Int,
        height: Int,
        maxSide: Int,
    ): Int {
        if (width <= 0 || height <= 0) {
            return 1
        }
        var sampleSize = 1
        var sampledWidth = width
        var sampledHeight = height
        while (sampledWidth > maxSide || sampledHeight > maxSide) {
            sampledWidth /= 2
            sampledHeight /= 2
            sampleSize *= 2
        }
        return sampleSize.coerceAtLeast(1)
    }

    private fun createTempFile(suffix: String): File {
        return File.createTempFile("mail_${UUID.randomUUID()}_", suffix, tempDir)
    }

    private fun ensureCompressedFileName(source: String, extension: String): String {
        val base = source.substringBeforeLast('.', source).ifBlank { "photo" }
        return "$base${extension}"
    }

    private fun ensureJpegFileName(source: String): String = ensureCompressedFileName(source, ".jpg")

    companion object {
        private const val TEMP_DIR_NAME = "photo_mailer_temp"

        fun clearTempCache(context: Context) {
            val dedicatedDir = File(context.cacheDir, TEMP_DIR_NAME)
            if (dedicatedDir.exists()) {
                dedicatedDir.listFiles()?.forEach { file ->
                    runCatching {
                        if (file.isDirectory) {
                            file.deleteRecursively()
                        } else {
                            file.delete()
                        }
                    }
                }
            }

            context.cacheDir.listFiles()?.forEach { file ->
                if (file.isFile && file.name.startsWith("mail_")) {
                    runCatching { file.delete() }
                }
            }
        }
    }
}

private data class CompressionProfile(
    val quality: Int,
    val maxImageSidePx: Int,
    val format: Bitmap.CompressFormat = Bitmap.CompressFormat.JPEG,
) {
    /** Extension to use for compressed output file */
    val fileExtension: String get() = when (format) {
        Bitmap.CompressFormat.WEBP_LOSSY, Bitmap.CompressFormat.WEBP_LOSSLESS -> ".webp"
        else -> ".jpg"
    }

    /** MIME type for compressed output */
    val mimeType: String get() = when (format) {
        Bitmap.CompressFormat.WEBP_LOSSY, Bitmap.CompressFormat.WEBP_LOSSLESS -> "image/webp"
        else -> "image/jpeg"
    }

    companion object {
        fun fromPreset(preset: String): CompressionProfile {
            return when (preset.trim().lowercase()) {
                "jpeg_light" -> CompressionProfile(quality = 85, maxImageSidePx = 2560)
                "jpeg_medium" -> CompressionProfile(quality = 68, maxImageSidePx = 1920)
                "jpeg_strong" -> CompressionProfile(quality = 50, maxImageSidePx = 1280)
                "webp_light" -> CompressionProfile(
                    quality = 85,
                    maxImageSidePx = 2560,
                    format = Bitmap.CompressFormat.WEBP_LOSSY,
                )
                "webp_medium" -> CompressionProfile(
                    quality = 65,
                    maxImageSidePx = 1920,
                    format = Bitmap.CompressFormat.WEBP_LOSSY,
                )
                // Backward compat aliases
                "low" -> CompressionProfile(quality = 68, maxImageSidePx = 1600)
                "high" -> CompressionProfile(quality = 90, maxImageSidePx = 2560)
                else -> CompressionProfile(quality = 80, maxImageSidePx = 1920)
            }
        }
    }
}
