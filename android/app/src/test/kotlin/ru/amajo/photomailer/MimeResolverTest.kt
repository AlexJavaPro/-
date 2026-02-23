package ru.amajo.photomailer

import org.junit.Assert.assertEquals
import org.junit.Test
import ru.amajo.photomailer.mail.MimeResolver

class MimeResolverTest {
    @Test
    fun `jpg extension resolves to image type`() {
        assertEquals("image/jpeg", MimeResolver.fromFileName("photo.jpg"))
    }

    @Test
    fun `unknown extension falls back to octet stream`() {
        assertEquals("application/octet-stream", MimeResolver.fromFileName("file.unknownext"))
    }
}

