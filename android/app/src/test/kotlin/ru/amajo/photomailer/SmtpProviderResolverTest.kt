package ru.amajo.photomailer

import org.junit.Assert.assertEquals
import org.junit.Test
import ru.amajo.photomailer.mail.SmtpProviderResolver

class SmtpProviderResolverTest {
    @Test
    fun resolvesYandexByDomain() {
        val endpoint = SmtpProviderResolver.resolveBySenderEmail("user@yandex.ru")
        assertEquals("smtp.yandex.com", endpoint.host)
        assertEquals(465, endpoint.port)
    }

    @Test
    fun resolvesGmailByDomain() {
        val endpoint = SmtpProviderResolver.resolveBySenderEmail("user@gmail.com")
        assertEquals("smtp.gmail.com", endpoint.host)
        assertEquals(465, endpoint.port)
    }

    @Test
    fun resolvesMailRuByDomain() {
        val endpoint = SmtpProviderResolver.resolveBySenderEmail("user@mail.ru")
        assertEquals("smtp.mail.ru", endpoint.host)
        assertEquals(465, endpoint.port)
    }

    @Test
    fun defaultsToYandexForUnknownDomain() {
        val endpoint = SmtpProviderResolver.resolveBySenderEmail("user@example.com")
        assertEquals("smtp.yandex.com", endpoint.host)
        assertEquals(465, endpoint.port)
    }
}
