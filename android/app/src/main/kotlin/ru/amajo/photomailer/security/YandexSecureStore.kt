package ru.amajo.photomailer.security

import android.content.Context
import android.util.Patterns
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

data class YandexAuthSession(
    val token: String,
    val email: String,
    val login: String,
    val userId: String,
    val userIdentifier: String,
    val savedAtMillis: Long,
) {
    val smtpIdentity: String
        get() {
            val normalizedEmail = email.trim()
            if (normalizedEmail.isNotBlank() &&
                Patterns.EMAIL_ADDRESS.matcher(normalizedEmail).matches()
            ) {
                return normalizedEmail
            }
            return ""
        }
}

class YandexSecureStore(
    context: Context,
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val preferences = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun saveSession(
        token: String,
        email: String,
        login: String = "",
        userId: String = "",
    ) {
        val normalizedEmail = email.trim()
            .takeIf { it.isNotBlank() && Patterns.EMAIL_ADDRESS.matcher(it).matches() }
            .orEmpty()
        val normalizedLogin = login.trim()
        val normalizedUserId = userId.trim()
        val identifier = normalizedEmail
            .takeIf { it.isNotBlank() }
            ?: normalizedLogin.takeIf { it.isNotBlank() }
            ?: normalizedUserId.takeIf { it.isNotBlank() }
            ?: "yandex_user"

        preferences.edit()
            .putString(KEY_TOKEN, token.trim())
            .putString(KEY_EMAIL, normalizedEmail)
            .putString(KEY_LOGIN, normalizedLogin)
            .putString(KEY_USER_ID, normalizedUserId)
            .putString(KEY_IDENTIFIER, identifier)
            .putLong(KEY_SAVED_AT, System.currentTimeMillis())
            .putBoolean(KEY_SMTP_READY, false)
            .apply()
    }

    fun loadSession(): YandexAuthSession? {
        val token = preferences.getString(KEY_TOKEN, null)?.trim().orEmpty()
        val email = preferences.getString(KEY_EMAIL, null)?.trim().orEmpty()
        val login = preferences.getString(KEY_LOGIN, null)?.trim().orEmpty()
        val userId = preferences.getString(KEY_USER_ID, null)?.trim().orEmpty()
        val storedIdentifier = preferences.getString(KEY_IDENTIFIER, null)?.trim().orEmpty()
        val identifier = storedIdentifier
            .ifBlank {
                email
                    .takeIf { it.isNotBlank() }
                    ?: login.takeIf { it.isNotBlank() }
                    ?: userId.takeIf { it.isNotBlank() }
                    ?: ""
            }

        if (token.isEmpty() || identifier.isEmpty()) {
            return null
        }
        val savedAt = preferences.getLong(KEY_SAVED_AT, 0L)
        return YandexAuthSession(
            token = token,
            email = email,
            login = login,
            userId = userId,
            userIdentifier = identifier,
            savedAtMillis = savedAt,
        )
    }

    fun clearSession() {
        preferences.edit()
            .remove(KEY_TOKEN)
            .remove(KEY_EMAIL)
            .remove(KEY_LOGIN)
            .remove(KEY_USER_ID)
            .remove(KEY_IDENTIFIER)
            .remove(KEY_SAVED_AT)
            .remove(KEY_SMTP_READY)
            .apply()
    }

    fun isSmtpReady(): Boolean {
        val hasSession = loadSession() != null
        if (!hasSession) {
            return false
        }
        return preferences.getBoolean(KEY_SMTP_READY, false)
    }

    fun setSmtpReady(ready: Boolean) {
        preferences.edit()
            .putBoolean(KEY_SMTP_READY, ready)
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "secure_mail_prefs"
        private const val KEY_TOKEN = "yandex_oauth_token"
        private const val KEY_EMAIL = "yandex_default_email"
        private const val KEY_LOGIN = "yandex_login"
        private const val KEY_USER_ID = "yandex_user_id"
        private const val KEY_IDENTIFIER = "yandex_user_identifier"
        private const val KEY_SAVED_AT = "yandex_token_saved_at"
        private const val KEY_SMTP_READY = "yandex_smtp_ready"
    }
}
