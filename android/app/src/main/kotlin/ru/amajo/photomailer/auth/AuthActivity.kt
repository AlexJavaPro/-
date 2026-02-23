package ru.amajo.photomailer.auth

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import com.yandex.authsdk.YandexAuthLoginOptions
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthResult
import com.yandex.authsdk.YandexAuthSdk
import com.yandex.authsdk.internal.strategy.LoginType
import java.security.MessageDigest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import ru.amajo.photomailer.security.YandexAuthSession
import ru.amajo.photomailer.security.YandexSecureStore

class AuthActivity : ComponentActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val secureStore by lazy { YandexSecureStore(applicationContext) }
    private val userInfoApi by lazy { YandexUserInfoApi() }
    private var previousSession: YandexAuthSession? = null
    private val sdk by lazy {
        YandexAuthSdk.create(
            YandexAuthOptions(this as Context, true),
        )
    }

    private lateinit var authLauncher: ActivityResultLauncher<YandexAuthLoginOptions>
    private var attemptedBrowserFallback = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        previousSession = secureStore.loadSession()

        authLauncher = registerForActivityResult(sdk.contract) { authResult ->
            handleAuthResult(authResult)
        }

        launchAuth(useBrowserFallback = false)
    }

    private fun handleAuthResult(result: YandexAuthResult) {
        when (result) {
            is YandexAuthResult.Success -> {
                val token = result.token.value.trim()
                if (token.isBlank()) {
                    finishWithFailure("Получен пустой OAuth-токен")
                    return
                }
                scope.launch {
                    runCatching {
                        withContext(Dispatchers.IO) {
                            userInfoApi.loadProfile(token)
                        }
                    }.onSuccess { profile ->
                        val identifier = profile.userIdentifier().ifBlank {
                            fallbackIdentifierFromToken(token)
                        }
                        val email = profile.bestEmailOrNull().orEmpty()
                        secureStore.saveSession(
                            token = token,
                            email = email,
                            login = profile.login.ifBlank { identifier },
                            userId = profile.id,
                        )
                        finishWithSuccess(email = email, identifier = identifier)
                    }.onFailure { error ->
                        when (error) {
                            is YandexUserInfoApi.UnauthorizedException -> {
                                secureStore.clearSession()
                                finishWithFailure("Сессия Яндекса устарела. Повторите вход.")
                            }
                            else -> {
                                // Если профиль недоступен (например, нет email/scope или временный сбой сети),
                                // вход считаем успешным и сохраняем максимально полезные данные.
                                val lastKnownEmail = previousSession?.email.orEmpty()
                                val lastKnownLogin = previousSession?.login.orEmpty()
                                val lastKnownUserId = previousSession?.userId.orEmpty()
                                val fallbackIdentifier = lastKnownUserId.ifBlank {
                                    fallbackIdentifierFromToken(token)
                                }
                                secureStore.saveSession(
                                    token = token,
                                    email = lastKnownEmail,
                                    login = lastKnownLogin,
                                    userId = fallbackIdentifier,
                                )
                                finishWithSuccess(
                                    email = lastKnownEmail,
                                    identifier = fallbackIdentifier,
                                )
                            }
                        }
                    }
                }
            }

            is YandexAuthResult.Failure -> {
                if (!attemptedBrowserFallback && shouldRetryInBrowser(result.exception)) {
                    attemptedBrowserFallback = true
                    launchAuth(useBrowserFallback = true)
                    return
                }
                finishWithFailure(mapAuthFailureMessage(result.exception))
            }

            else -> {
                finishCancelled()
            }
        }
    }

    private fun launchAuth(useBrowserFallback: Boolean) {
        val options = if (useBrowserFallback) {
            YandexAuthLoginOptions(LoginType.CHROME_TAB)
        } else {
            YandexAuthLoginOptions()
        }
        authLauncher.launch(options)
    }

    private fun shouldRetryInBrowser(error: Throwable): Boolean {
        val message = (error.message ?: "").lowercase()
        return message.contains("email") ||
            message.contains("profile") ||
            message.contains("native") ||
            message.contains("login failed")
    }

    private fun mapAuthFailureMessage(error: Throwable): String {
        val raw = (error.message ?: "").trim()
        if (raw.isBlank()) {
            return "Ошибка авторизации Яндекса"
        }
        val lower = raw.lowercase()
        if (lower.contains("email") || lower.contains("profile")) {
            return "Не удалось получить профиль аккаунта Яндекса. Проверьте разрешение login:email и повторите вход."
        }
        if (lower.contains("signature") || lower.contains("sha") || lower.contains("fingerprint")) {
            return "Ошибка подписи Android. Проверьте SHA-256 приложения в настройках OAuth."
        }
        return raw
    }

    private fun fallbackIdentifierFromToken(token: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(token.toByteArray(Charsets.UTF_8))
        val suffix = digest
            .take(8)
            .joinToString(separator = "") { byte -> "%02x".format(byte) }
        return "yandex_$suffix"
    }

    private fun finishWithSuccess(
        email: String,
        identifier: String,
    ) {
        setResult(
            Activity.RESULT_OK,
            Intent().apply {
                putExtra(EXTRA_EMAIL, email)
                putExtra(EXTRA_IDENTIFIER, identifier)
            },
        )
        finish()
    }

    private fun finishWithFailure(message: String) {
        setResult(
            Activity.RESULT_CANCELED,
            Intent().apply {
                putExtra(EXTRA_ERROR, message)
            },
        )
        finish()
    }

    private fun finishCancelled() {
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_EMAIL = "extra_email"
        const val EXTRA_IDENTIFIER = "extra_identifier"
        const val EXTRA_ERROR = "extra_error"

        fun createIntent(context: Context): Intent {
            return Intent(context, AuthActivity::class.java)
        }
    }
}

