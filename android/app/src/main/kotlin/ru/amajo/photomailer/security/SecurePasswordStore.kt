package ru.amajo.photomailer.security

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.MessageDigest
import java.security.SecureRandom

class SecurePasswordStore(
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

    fun savePassword(password: String) {
        val normalized = normalizeAppPassword(password)
        require(normalized.isNotBlank()) { "Password is empty" }
        preferences.edit()
            .putString(KEY_PASSWORD, normalized)
            .apply()
    }

    fun loadPassword(): String? {
        return preferences.getString(KEY_PASSWORD, null)
    }

    fun clearPassword() {
        preferences.edit()
            .remove(KEY_PASSWORD)
            .apply()
    }

    fun saveJobPassword(jobId: String, password: String) {
        val key = jobPasswordKey(jobId)
        preferences.edit()
            .putString(key, password)
            .apply()
    }

    fun loadJobPassword(jobId: String): String? {
        return preferences.getString(jobPasswordKey(jobId), null)
    }

    fun clearJobPassword(jobId: String) {
        preferences.edit()
            .remove(jobPasswordKey(jobId))
            .apply()
    }

    fun savePattern(pattern: String) {
        require(pattern.isNotBlank()) { "Pattern is empty" }
        val salt = ByteArray(PATTERN_SALT_SIZE)
        secureRandom.nextBytes(salt)
        val hash = hashPattern(pattern = pattern, salt = salt)

        preferences.edit()
            .putString(KEY_PATTERN_SALT, Base64.encodeToString(salt, Base64.NO_WRAP))
            .putString(KEY_PATTERN_HASH, Base64.encodeToString(hash, Base64.NO_WRAP))
            .apply()
    }

    fun verifyPattern(pattern: String): Boolean {
        if (pattern.isBlank()) {
            return false
        }

        val saltEncoded = preferences.getString(KEY_PATTERN_SALT, null) ?: return false
        val hashEncoded = preferences.getString(KEY_PATTERN_HASH, null) ?: return false

        val salt = runCatching { Base64.decode(saltEncoded, Base64.NO_WRAP) }
            .getOrElse { return false }
        val expectedHash = runCatching { Base64.decode(hashEncoded, Base64.NO_WRAP) }
            .getOrElse { return false }

        val actualHash = hashPattern(pattern = pattern, salt = salt)
        return MessageDigest.isEqual(expectedHash, actualHash)
    }

    fun hasPattern(): Boolean {
        val salt = preferences.getString(KEY_PATTERN_SALT, null)
        val hash = preferences.getString(KEY_PATTERN_HASH, null)
        return !salt.isNullOrBlank() && !hash.isNullOrBlank()
    }

    fun clearPattern() {
        preferences.edit()
            .remove(KEY_PATTERN_SALT)
            .remove(KEY_PATTERN_HASH)
            .apply()
    }

    private fun hashPattern(pattern: String, salt: ByteArray): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(salt)
        digest.update(pattern.toByteArray(Charsets.UTF_8))
        return digest.digest()
    }

    private fun jobPasswordKey(jobId: String): String {
        return KEY_JOB_PASSWORD_PREFIX + jobId
    }

    companion object {
        private const val PREFS_NAME = "secure_mail_prefs"
        private const val KEY_PASSWORD = "yandex_app_password"
        private const val KEY_JOB_PASSWORD_PREFIX = "send_job_password_"
        private const val KEY_PATTERN_SALT = "app_lock_pattern_salt"
        private const val KEY_PATTERN_HASH = "app_lock_pattern_hash"
        private const val PATTERN_SALT_SIZE = 16
        private val secureRandom = SecureRandom()
    }

    private fun normalizeAppPassword(raw: String): String {
        return raw
            .trim()
            .replace(Regex("[\\s-]+"), "")
    }
}
