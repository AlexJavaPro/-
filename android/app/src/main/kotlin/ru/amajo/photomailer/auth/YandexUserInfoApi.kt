package ru.amajo.photomailer.auth

import java.io.IOException
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class YandexUserInfoApi {
    data class YandexUserProfile(
        val id: String,
        val login: String,
        val defaultEmail: String?,
        val emails: List<String>,
    ) {
        fun bestEmailOrNull(): String? {
            if (!defaultEmail.isNullOrBlank()) {
                return defaultEmail.trim()
            }
            return emails.firstOrNull { it.isNotBlank() }?.trim()
        }

        fun userIdentifier(): String {
            return bestEmailOrNull()
                ?: login.trim().takeIf { it.isNotBlank() }
                ?: id.trim().takeIf { it.isNotBlank() }
                ?: ""
        }
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build()

    fun loadProfile(token: String): YandexUserProfile {
        if (token.isBlank()) {
            throw IOException("OAuth token is empty")
        }

        val request = Request.Builder()
            .url(USER_INFO_ENDPOINT)
            .addHeader("Authorization", "OAuth $token")
            .get()
            .build()

        httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                if (response.code == 401) {
                    throw UnauthorizedException("Yandex OAuth token is expired or invalid")
                }
                if (response.code == 403) {
                    throw AccessDeniedException("Yandex profile endpoint returned HTTP 403")
                }
                throw IOException("Yandex user info request failed: HTTP ${response.code}")
            }
            val raw = response.body?.string().orEmpty()
            if (raw.isBlank()) {
                throw IOException("Yandex user info response is empty")
            }

            val json = JSONObject(raw)
            val id = json.optString("id", "").trim()
            val login = json.optString("login", "").trim()
            val defaultEmail = json.optString("default_email", "").trim()
                .ifBlank { null }
            val emails = buildList {
                val array = json.optJSONArray("emails")
                if (array != null) {
                    for (index in 0 until array.length()) {
                        val email = array.optString(index, "").trim()
                        if (email.isNotBlank()) {
                            add(email)
                        }
                    }
                }
            }
            val profile = YandexUserProfile(
                id = id,
                login = login,
                defaultEmail = defaultEmail,
                emails = emails,
            )
            if (profile.userIdentifier().isBlank()) {
                throw IOException("Yandex profile does not contain id/login/email")
            }
            return profile
        }
    }

    class UnauthorizedException(
        message: String,
    ) : IOException(message)

    class AccessDeniedException(
        message: String,
    ) : IOException(message)

    companion object {
        private const val USER_INFO_ENDPOINT = "https://login.yandex.ru/info?format=json"
    }
}
