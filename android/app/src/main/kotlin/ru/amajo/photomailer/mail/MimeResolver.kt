package ru.amajo.photomailer.mail

import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import java.util.Locale
import ru.amajo.photomailer.db.PhotoEntity

class MimeResolver(
    private val context: Context,
) {
    fun resolve(photo: PhotoEntity): String {
        photo.mimeType
            ?.trim()
            ?.takeIf { it.contains('/') }
            ?.let { return it }

        runCatching {
            context.contentResolver.getType(Uri.parse(photo.uri))
        }.getOrNull()
            ?.takeIf { it.contains('/') }
            ?.let { return it }

        return fromFileName(photo.name)
    }

    companion object {
        fun fromFileName(fileName: String?): String {
            val extension = fileName
                ?.substringAfterLast('.', "")
                ?.lowercase(Locale.US)
                ?.trim()
                .orEmpty()
            if (extension.isBlank()) {
                return "application/octet-stream"
            }
            return MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
        }
    }
}

