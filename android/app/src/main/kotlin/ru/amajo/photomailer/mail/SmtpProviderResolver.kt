package ru.amajo.photomailer.mail

data class SmtpEndpoint(
    val host: String,
    val port: Int,
    val providerLabel: String,
)

object SmtpProviderResolver {

    /**
     * Возвращает единственный endpoint (обратная совместимость).
     * Приоритет: порт 465 (SMTPS/SSL).
     */
    fun resolveBySenderEmail(senderEmail: String): SmtpEndpoint =
        resolveOrderedBySenderEmail(senderEmail).first()

    /**
     * Возвращает список endpoint-ов в порядке приоритета для fallback-перебора.
     *
     * Яндекс поддерживает два варианта:
     *  • 465 — SMTPS (SSL сразу, предпочтительно)
     *  • 587 — STARTTLS (TLS поверх plain, запасной вариант если 465 заблокирован оператором)
     */
    fun resolveOrderedBySenderEmail(senderEmail: String): List<SmtpEndpoint> {
        return listOf(
            SmtpEndpoint(
                host = "smtp.yandex.ru",
                port = 465,
                providerLabel = "Yandex:465",
            ),
            SmtpEndpoint(
                host = "smtp.yandex.ru",
                port = 587,
                providerLabel = "Yandex:587",
            ),
        )
    }
}
