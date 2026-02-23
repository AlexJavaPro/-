package ru.amajo.photomailer.mail

/**
 * Утилиты для работы со SMTP-паролями приложений.
 *
 * Вынесены в отдельный объект, чтобы одна и та же логика нормализации
 * использовалась как в NativeBridgeHandler (self-test), так и в SendMailWorker
 * (реальная фоновая отправка).
 */
object SmtpUtils {

    /**
     * Нормализует пароль приложения Яндекса: убирает пробелы и дефисы.
     *
     * Яндекс выдаёт пароли в формате `abcd-efgh-ijkl-mnop` для удобства чтения,
     * но SMTP-сервер ожидает пароль без разделителей — `abcdefghijklmnop`.
     */
    fun normalizeAppPassword(raw: String): String =
        raw.trim().replace(Regex("[\\s\\-]+"), "")

    /**
     * Минимальная длина пароля приложения (после нормализации).
     */
    const val MIN_PASSWORD_LENGTH = 8

    /**
     * Проверяет, что нормализованный пароль соответствует минимальной длине.
     */
    fun isValidAppPassword(normalized: String): Boolean =
        normalized.length >= MIN_PASSWORD_LENGTH
}
