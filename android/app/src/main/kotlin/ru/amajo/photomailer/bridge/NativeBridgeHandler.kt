package ru.amajo.photomailer.bridge

import android.app.Activity
import android.util.Log
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.util.Patterns
import androidx.room.withTransaction
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID
import jakarta.mail.AuthenticationFailedException
import jakarta.mail.MessagingException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import ru.amajo.photomailer.accessibility.YandexMailAccessibilityService
import ru.amajo.photomailer.auth.AuthActivity
import ru.amajo.photomailer.auth.YandexUserInfoApi
import ru.amajo.photomailer.automation.ShareAutomationForegroundService
import ru.amajo.photomailer.db.AppDatabase
import ru.amajo.photomailer.db.JobEntity
import ru.amajo.photomailer.db.JobState
import ru.amajo.photomailer.db.LogEntity
import ru.amajo.photomailer.db.PhotoEntity
import ru.amajo.photomailer.mail.SmtpAuthMode
import ru.amajo.photomailer.mail.SmtpProviderResolver
import ru.amajo.photomailer.mail.SmtpSender
import ru.amajo.photomailer.mail.SmtpUtils
import ru.amajo.photomailer.picker.SafPhotoPicker
import ru.amajo.photomailer.security.SecurePasswordStore
import ru.amajo.photomailer.security.YandexAuthSession
import ru.amajo.photomailer.security.YandexSecureStore
import ru.amajo.photomailer.work.SendWorkScheduler

class NativeBridgeHandler(
    private val activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val db = AppDatabase.getInstance(activity.applicationContext)
    private val secureStore = SecurePasswordStore(activity.applicationContext)
    private val yandexSecureStore = YandexSecureStore(activity.applicationContext)
    private val picker = SafPhotoPicker(activity)
    private val workScheduler = SendWorkScheduler(activity.applicationContext)
    private val userInfoApi = YandexUserInfoApi()

    private var pendingYandexAuthResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_CODE_YANDEX_AUTH) {
            return false
        }
        val pending = pendingYandexAuthResult
        pendingYandexAuthResult = null
        if (pending == null) {
            return true
        }

        if (resultCode == Activity.RESULT_OK) {
            val email = data?.getStringExtra(AuthActivity.EXTRA_EMAIL)?.trim().orEmpty()
            val identifier = data?.getStringExtra(AuthActivity.EXTRA_IDENTIFIER)
                ?.trim()
                .orEmpty()
                .ifBlank { email }
            pending.success(
                mapOf(
                    "authorized" to identifier.isNotEmpty(),
                    "email" to email,
                    "identifier" to identifier,
                ),
            )
            return true
        }

        val message = data?.getStringExtra(AuthActivity.EXTRA_ERROR)
            ?.trim()
            .orEmpty()
            .ifBlank { "Авторизация Яндекса отменена" }
        pending.error("yandex_auth_failed", message, null)
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_PICK_PHOTOS -> {
                val source = call.argument<String>("source")
                picker.pick(result, source)
            }
            METHOD_SAVE_APP_PATTERN -> saveAppPattern(call, result)
            METHOD_VERIFY_APP_PATTERN -> verifyAppPattern(call, result)
            METHOD_HAS_APP_PATTERN -> hasAppPattern(result)
            METHOD_CLEAR_APP_PATTERN -> clearAppPattern(result)
            METHOD_OPEN_EXTERNAL_EMAIL -> openExternalEmail(call, result)
            METHOD_GET_YANDEX_AUTH_STATE -> getYandexAuthState(result)
            METHOD_START_YANDEX_LOGIN -> startYandexLogin(result)
            METHOD_LOGOUT_YANDEX -> logoutYandex(result)
            METHOD_GET_ACCESSIBILITY_STATE -> getAccessibilityState(result)
            METHOD_OPEN_ACCESSIBILITY_SETTINGS -> openAccessibilitySettings(result)
            METHOD_START_SHARE_AUTOMATION_SERIES -> startShareAutomationSeries(call, result)
            METHOD_GET_SHARE_AUTOMATION_STATE -> getShareAutomationState(result)
            METHOD_RESUME_SHARE_AUTOMATION -> resumeShareAutomation(result)
            METHOD_CANCEL_SHARE_AUTOMATION -> cancelShareAutomation(result)
            METHOD_OPEN_CURRENT_SHARE_BATCH_MANUALLY -> openCurrentShareBatchManually(result)
            METHOD_ENQUEUE_SEND_JOB -> enqueueSendJob(call, result)
            METHOD_GET_JOB_STATUS -> getJobStatus(call, result)
            METHOD_GET_JOB_LOGS -> getJobLogs(call, result)
            METHOD_CANCEL_SEND_JOB -> cancelSendJob(call, result)
            METHOD_GET_LATEST_JOB_STATUS -> getLatestJobStatus(result)
            METHOD_RUN_SMTP_SELF_TEST -> runSmtpSelfTest(call, result)
            METHOD_SAVE_AND_RUN_SMTP_SELF_TEST -> saveAndRunSmtpSelfTest(call, result)
            METHOD_SAVE_SMTP_APP_PASSWORD -> saveSmtpAppPassword(call, result)
            METHOD_HAS_SMTP_APP_PASSWORD -> hasSmtpAppPassword(result)
            METHOD_CLEAR_SMTP_APP_PASSWORD -> clearSmtpAppPassword(result)
            else -> result.notImplemented()
        }
    }

    private fun saveAppPattern(call: MethodCall, result: MethodChannel.Result) {
        val pattern = call.argument<String>("pattern")?.trim().orEmpty()
        if (pattern.isBlank()) {
            result.error("bad_request", "Пустой графический пароль", null)
            return
        }

        runCatching {
            secureStore.savePattern(pattern)
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("save_pattern_failed", error.message, null)
        }
    }

    private fun verifyAppPattern(call: MethodCall, result: MethodChannel.Result) {
        val pattern = call.argument<String>("pattern")?.trim().orEmpty()
        if (pattern.isBlank()) {
            result.success(mapOf("valid" to false))
            return
        }

        runCatching {
            secureStore.verifyPattern(pattern)
        }.onSuccess { valid ->
            result.success(mapOf("valid" to valid))
        }.onFailure { error ->
            result.error("verify_pattern_failed", error.message, null)
        }
    }

    private fun hasAppPattern(result: MethodChannel.Result) {
        runCatching {
            secureStore.hasPattern()
        }.onSuccess { hasPattern ->
            result.success(mapOf("hasPattern" to hasPattern))
        }.onFailure { error ->
            result.error("has_pattern_failed", error.message, null)
        }
    }

    private fun clearAppPattern(result: MethodChannel.Result) {
        runCatching {
            secureStore.clearPattern()
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("clear_pattern_failed", error.message, null)
        }
    }

    private fun saveSmtpAppPassword(call: MethodCall, result: MethodChannel.Result) {
        val password = normalizeSmtpAppPassword(
            call.argument<String>("password").orEmpty(),
        )
        if (password.isBlank()) {
            result.error("smtp_password_required", "Введите пароль приложения", null)
            return
        }
        if (!isValidSmtpAppPassword(password)) {
            result.error(
                "smtp_password_invalid",
                "Пароль приложения слишком короткий. Минимум 8 символов.",
                null,
            )
            return
        }
        runCatching {
            secureStore.savePassword(password)
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("save_smtp_password_failed", error.message, null)
        }
    }

    private fun hasSmtpAppPassword(result: MethodChannel.Result) {
        runCatching {
            !secureStore.loadPassword().isNullOrBlank()
        }.onSuccess { hasPassword ->
            result.success(mapOf("hasPassword" to hasPassword))
        }.onFailure { error ->
            result.error("has_smtp_password_failed", error.message, null)
        }
    }

    private fun clearSmtpAppPassword(result: MethodChannel.Result) {
        runCatching {
            secureStore.clearPassword()
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("clear_smtp_password_failed", error.message, null)
        }
    }

    private fun getYandexAuthState(result: MethodChannel.Result) {
        runCatching {
            yandexSecureStore.loadSession()
        }.onSuccess { session ->
            result.success(
                mapOf(
                    "authorized" to (session != null),
                    "email" to (session?.email ?: ""),
                    "login" to (session?.login ?: ""),
                    "userId" to (session?.userId ?: ""),
                    "identifier" to (session?.userIdentifier ?: ""),
                    "savedAtMillis" to (session?.savedAtMillis ?: 0L),
                    "smtpReady" to yandexSecureStore.isSmtpReady(),
                    "smtpIdentity" to (session?.smtpIdentity ?: ""),
                ),
            )
        }.onFailure { error ->
            result.error("yandex_auth_state_failed", error.message, null)
        }
    }

    private fun startYandexLogin(result: MethodChannel.Result) {
        if (pendingYandexAuthResult != null) {
            result.error("yandex_auth_busy", "Авторизация уже выполняется", null)
            return
        }

        pendingYandexAuthResult = result
        runCatching {
            activity.startActivityForResult(
                AuthActivity.createIntent(activity),
                REQUEST_CODE_YANDEX_AUTH,
            )
        }.onFailure { error ->
            pendingYandexAuthResult = null
            result.error(
                "yandex_auth_start_failed",
                error.message ?: "Не удалось открыть экран авторизации Яндекса",
                null,
            )
        }
    }

    private fun logoutYandex(result: MethodChannel.Result) {
        runCatching {
            yandexSecureStore.clearSession()
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("yandex_logout_failed", error.message, null)
        }
    }

    private fun getAccessibilityState(result: MethodChannel.Result) {
        runCatching {
            YandexMailAccessibilityService.getState(activity.applicationContext)
        }.onSuccess { state ->
            result.success(state)
        }.onFailure { error ->
            result.error("accessibility_state_failed", error.message, null)
        }
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        runCatching {
            YandexMailAccessibilityService.openAccessibilitySettings(activity.applicationContext)
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("open_accessibility_settings_failed", error.message, null)
        }
    }

    private fun startShareAutomationSeries(call: MethodCall, result: MethodChannel.Result) {
        val recipientEmail = call.argument<String>("recipientEmail")?.trim().orEmpty()
        val subjectInput = call.argument<String>("subjectInput")?.trim().orEmpty()
        val limitBytes = call.argument<Number>("limitBytes")?.toLong() ?: -1L
        val photos = parseSendPhotos(call)

        if (recipientEmail.isBlank()) {
            result.error("bad_request", "Требуется email получателя", null)
            return
        }
        if (limitBytes <= 0L) {
            result.error("bad_request", "Некорректный лимит размера письма", null)
            return
        }
        if (photos.isEmpty()) {
            result.error("bad_request", "Фотографии не переданы", null)
            return
        }
        if (yandexSecureStore.loadSession() == null) {
            result.error("unauthorized", "Требуется вход в Яндекс", null)
            return
        }
        if (!YandexMailAccessibilityService.isEnabled(activity.applicationContext)) {
            result.error(
                "accessibility_disabled",
                "Включите сервис доступности для автосерии",
                null,
            )
            return
        }

        runCatching {
            ShareAutomationForegroundService.startSeries(
                context = activity.applicationContext,
                recipientEmail = recipientEmail,
                subjectInput = subjectInput,
                limitBytes = limitBytes,
                photos = photos.map { photo ->
                    mapOf(
                        "uri" to photo.uri,
                        "name" to photo.name,
                        "sizeBytes" to photo.sizeBytes,
                        "mimeType" to photo.mimeType,
                    )
                },
            )
            ShareAutomationForegroundService.getState(activity.applicationContext).toMap()
        }.onSuccess { state ->
            result.success(state)
        }.onFailure { error ->
            result.error("start_share_automation_failed", error.message, null)
        }
    }

    private fun getShareAutomationState(result: MethodChannel.Result) {
        runCatching {
            ShareAutomationForegroundService.getState(activity.applicationContext).toMap()
        }.onSuccess { state ->
            result.success(state)
        }.onFailure { error ->
            result.error("share_automation_state_failed", error.message, null)
        }
    }

    private fun resumeShareAutomation(result: MethodChannel.Result) {
        if (yandexSecureStore.loadSession() == null) {
            result.error("unauthorized", "Требуется вход в Яндекс", null)
            return
        }
        if (!YandexMailAccessibilityService.isEnabled(activity.applicationContext)) {
            result.error(
                "accessibility_disabled",
                "Включите сервис доступности для автосерии",
                null,
            )
            return
        }
        runCatching {
            ShareAutomationForegroundService.resume(activity.applicationContext)
            ShareAutomationForegroundService.getState(activity.applicationContext).toMap()
        }.onSuccess { state ->
            result.success(state)
        }.onFailure { error ->
            result.error("resume_share_automation_failed", error.message, null)
        }
    }

    private fun cancelShareAutomation(result: MethodChannel.Result) {
        runCatching {
            ShareAutomationForegroundService.cancel(activity.applicationContext)
            ShareAutomationForegroundService.getState(activity.applicationContext).toMap()
        }.onSuccess { state ->
            result.success(state)
        }.onFailure { error ->
            result.error("cancel_share_automation_failed", error.message, null)
        }
    }

    private fun openCurrentShareBatchManually(result: MethodChannel.Result) {
        runCatching {
            ShareAutomationForegroundService.openCurrentBatchManually(activity.applicationContext)
            ShareAutomationForegroundService.getState(activity.applicationContext).toMap()
        }.onSuccess { state ->
            result.success(state)
        }.onFailure { error ->
            result.error("open_current_share_batch_manually_failed", error.message, null)
        }
    }

    private fun openExternalEmail(call: MethodCall, result: MethodChannel.Result) {
        val recipientEmail = call.argument<String>("recipientEmail")?.trim().orEmpty()
        val subject = call.argument<String>("subject")?.trim().orEmpty()
        val body = call.argument<String>("body")?.trim().orEmpty()
        val chooserTitle = call.argument<String>("chooserTitle")
            ?.trim()
            .orEmpty()
            .ifBlank { "Выберите почтовое приложение" }
        val targetPackage = call.argument<String>("targetPackage")
            ?.trim()
            .orEmpty()
        val photos = parseSendPhotos(call)

        if (photos.isEmpty()) {
            result.error("bad_request", "Фотографии не переданы", null)
            return
        }

        runCatching {
            val uris = ArrayList<Uri>(photos.size)
            photos.forEach { photo ->
                uris.add(Uri.parse(photo.uri))
            }

            val sendIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                type = resolveMimeType(photos)
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                if (targetPackage.isNotBlank()) {
                    `package` = targetPackage
                }
                if (recipientEmail.isNotBlank()) {
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(recipientEmail))
                }
                if (subject.isNotBlank()) {
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                }
                if (body.isNotBlank()) {
                    putExtra(Intent.EXTRA_TEXT, body)
                }
            }
            attachClipData(sendIntent, uris)
            if (targetPackage.isNotBlank()) {
                activity.startActivity(sendIntent)
            } else {
                val chooser = Intent.createChooser(sendIntent, chooserTitle)
                activity.startActivity(chooser)
            }
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            val message = when (error) {
                is ActivityNotFoundException -> "Почтовое приложение не найдено"
                else -> error.message ?: "Не удалось открыть почтовое приложение"
            }
            result.error("open_external_email_failed", message, null)
        }
    }

    private fun resolveMimeType(photos: List<SendPhoto>): String {
        val mimeTypes = photos
            .mapNotNull { photo -> photo.mimeType?.takeIf { it.isNotBlank() } }
            .toSet()
        return if (mimeTypes.size == 1) mimeTypes.first() else "image/*"
    }

    private fun attachClipData(intent: Intent, uris: List<Uri>) {
        if (uris.isEmpty()) {
            return
        }
        val clipData = ClipData.newUri(activity.contentResolver, "photos", uris.first())
        for (index in 1 until uris.size) {
            clipData.addItem(ClipData.Item(uris[index]))
        }
        intent.clipData = clipData
    }

    private fun enqueueSendJob(call: MethodCall, result: MethodChannel.Result) {
        val request = parseRequest(call)
        if (request == null) {
            result.error("bad_request", "Некорректные параметры отправки", null)
            return
        }
        if (request.photos.isEmpty()) {
            result.error("bad_request", "Фотографии не переданы", null)
            return
        }
        if (request.limitBytes <= 0) {
            result.error("bad_request", "Лимит должен быть больше 0", null)
            return
        }

        val authSession = yandexSecureStore.loadSession()
        if (authSession == null) {
            result.error("unauthorized", "Требуется вход в Яндекс", null)
            return
        }
        if (!Patterns.EMAIL_ADDRESS.matcher(authSession.smtpIdentity).matches()) {
            result.error(
                "smtp_identity_missing",
                "Не удалось получить адрес отправителя из Яндекса. Войдите заново и повторите проверку отправки.",
                null,
            )
            return
        }
        if (!yandexSecureStore.isSmtpReady()) {
            result.error(
                "smtp_not_ready",
                "SMTP не подтвержден. Выполните тест отправки в настройках.",
                null,
            )
            return
        }

        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    val resolvedSession = ensureSmtpIdentity(authSession)
                    val now = System.currentTimeMillis()
                    val jobId = UUID.randomUUID().toString()
                    db.withTransaction {
                        insertJob(jobId, request, resolvedSession, now)
                    }
                    workScheduler.enqueue(jobId, request.compressionPreset)
                    jobId
                }
            }.onSuccess { jobId ->
                result.success(mapOf("jobId" to jobId))
            }.onFailure { error ->
                when {
                    error is YandexUserInfoApi.UnauthorizedException -> {
                        result.error(
                            "unauthorized",
                            "Сессия Яндекса устарела. Войдите снова.",
                            null,
                        )
                    }

                    error is SmtpIdentityMissingException -> {
                        result.error(
                            "smtp_identity_missing",
                            "Не удалось получить адрес отправителя из Яндекса. Войдите заново и повторите проверку отправки.",
                            null,
                        )
                    }

                    isNetworkError(error) -> {
                        result.error(
                            "network_error",
                            "Нет интернета. Повторите попытку позже.",
                            null,
                        )
                    }

                    else -> {
                        result.error("enqueue_failed", error.message, null)
                    }
                }
            }
        }
    }

    private suspend fun insertJob(
        jobId: String,
        request: SendJobRequest,
        authSession: YandexAuthSession,
        now: Long,
    ) {
        db.jobDao().insert(
            JobEntity(
                jobId = jobId,
                senderEmail = authSession.smtpIdentity,
                recipientEmail = request.recipientEmail,
                subjectInput = request.subjectInput,
                limitBytes = request.limitBytes,
                state = JobState.QUEUED,
                totalBatches = 0,
                sentBatches = 0,
                lastError = null,
                createdAt = now,
                updatedAt = now,
            ),
        )
        db.photoDao().insertAll(
            request.photos.map { photo ->
                PhotoEntity(
                    jobId = jobId,
                    uri = photo.uri,
                    name = photo.name,
                    sizeBytes = photo.sizeBytes,
                    mimeType = photo.mimeType,
                )
            },
        )
        db.logDao().insert(
            LogEntity(
                jobId = jobId,
                level = "INFO",
                message = "Создана задача отправки: файлов ${request.photos.size}",
                batchIndex = null,
                createdAt = now,
            ),
        )
    }

    private fun getJobStatus(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<String>("jobId")
        if (jobId.isNullOrBlank()) {
            result.error("bad_request", "Требуется jobId", null)
            return
        }

        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) { db.jobDao().findById(jobId) }
            }.onSuccess { job ->
                if (job == null) {
                    result.error("not_found", "Задача не найдена", null)
                    return@onSuccess
                }
                result.success(jobStatusMap(job))
            }.onFailure { error ->
                result.error("status_failed", error.message, null)
            }
        }
    }

    private fun getJobLogs(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<String>("jobId")
        if (jobId.isNullOrBlank()) {
            result.error("bad_request", "Требуется jobId", null)
            return
        }
        val afterId = (call.argument<Number>("afterId"))?.toLong()

        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    db.logDao().listByJob(jobId = jobId, afterId = afterId)
                }
            }.onSuccess { logs ->
                result.success(
                    logs.map { log ->
                        mapOf(
                            "id" to log.id,
                            "jobId" to log.jobId,
                            "level" to log.level,
                            "message" to log.message,
                            "batchIndex" to log.batchIndex,
                            "createdAt" to log.createdAt,
                        )
                    },
                )
            }.onFailure { error ->
                result.error("logs_failed", error.message, null)
            }
        }
    }

    private fun cancelSendJob(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<String>("jobId")
        if (jobId.isNullOrBlank()) {
            result.error("bad_request", "Требуется jobId", null)
            return
        }

        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    val job = db.jobDao().findById(jobId) ?: throw IllegalStateException("Задача не найдена")
                    val now = System.currentTimeMillis()
                    workScheduler.cancel(jobId)
                    db.jobDao().updateState(
                        jobId = jobId,
                        state = JobState.CANCELLED,
                        updatedAt = now,
                        lastError = "Остановлено пользователем",
                    )
                    db.logDao().insert(
                        LogEntity(
                            jobId = jobId,
                            level = "WARN",
                            message = "Отправка остановлена пользователем",
                            batchIndex = null,
                            createdAt = now,
                        ),
                    )
                    db.jobDao().findById(jobId)
                        ?: job.copy(
                            state = JobState.CANCELLED,
                            lastError = "Остановлено пользователем",
                            updatedAt = now,
                        )
                }
            }.onSuccess { updatedJob ->
                result.success(jobStatusMap(updatedJob))
            }.onFailure { error ->
                result.error("cancel_failed", error.message, null)
            }
        }
    }

    private fun getLatestJobStatus(result: MethodChannel.Result) {
        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    db.jobDao().findLatestActive() ?: db.jobDao().findLatest()
                }
            }.onSuccess { job ->
                result.success(job?.let(::jobStatusMap))
            }.onFailure { error ->
                result.error("latest_status_failed", error.message, null)
            }
        }
    }

    private fun runSmtpSelfTest(call: MethodCall, result: MethodChannel.Result) {
        val recipientEmail = call.argument<String>("recipientEmail")?.trim().orEmpty()
        if (recipientEmail.isNotBlank() && !Patterns.EMAIL_ADDRESS.matcher(recipientEmail).matches()) {
            result.error("validation_error", "Укажите корректный email получателя", null)
            return
        }
        runSmtpSelfTestInternal(
            recipientOverride = recipientEmail.ifBlank { null },
            passwordToSave = null,
            result = result,
        )
    }

    private fun saveAndRunSmtpSelfTest(call: MethodCall, result: MethodChannel.Result) {
        val rawPassword = call.argument<String>("appPassword")
        val normalizedPassword = normalizeSmtpAppPassword(rawPassword.orEmpty())
        val hasPasswordArgument = rawPassword != null
        if (hasPasswordArgument) {
            if (rawPassword.isNullOrBlank() || normalizedPassword.isBlank()) {
                result.error("smtp_password_required", "Введите пароль приложения", null)
                return
            }
            if (!isValidSmtpAppPassword(normalizedPassword)) {
                result.error(
                    "smtp_password_invalid",
                    "Пароль приложения слишком короткий. Минимум 8 символов.",
                    null,
                )
                return
            }
        }
        runSmtpSelfTestInternal(
            recipientOverride = null,
            passwordToSave = normalizedPassword.ifBlank { null },
            result = result,
        )
    }

    private fun runSmtpSelfTestInternal(
        recipientOverride: String?,
        passwordToSave: String?,
        result: MethodChannel.Result,
    ) {
        val authSession = yandexSecureStore.loadSession()
        if (authSession == null) {
            yandexSecureStore.setSmtpReady(false)
            result.error("unauthorized", "Требуется вход в Яндекс", null)
            return
        }

        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    if (!passwordToSave.isNullOrBlank()) {
                        secureStore.savePassword(passwordToSave)
                    }
                    val resolvedSession = ensureSmtpIdentity(authSession)
                    val recipientEmail = recipientOverride
                        ?.trim()
                        .orEmpty()
                        .ifBlank { resolvedSession.smtpIdentity.trim() }
                    if (recipientEmail.isBlank() ||
                        !Patterns.EMAIL_ADDRESS.matcher(recipientEmail).matches()
                    ) {
                        throw SmtpIdentityMissingException()
                    }

                    val appPassword = normalizeSmtpAppPassword(
                        secureStore.loadPassword().orEmpty(),
                    )
                    val smtpIdentities = buildSmtpIdentityCandidates(resolvedSession)
                    var lastAuthError: Throwable? = null
                    for (smtpIdentity in smtpIdentities) {
                        val endpoints = SmtpProviderResolver.resolveOrderedBySenderEmail(smtpIdentity)
                        var lastEndpointError: Throwable? = null
                        var selfTestMode: SmtpAuthMode? = null
                        for (endpoint in endpoints) {
                            val sender = SmtpSender(
                                senderEmail = smtpIdentity,
                                smtpHost = endpoint.host,
                                smtpPort = endpoint.port,
                                oauthToken = resolvedSession.token,
                                appPassword = appPassword,
                                useStartTls = endpoint.port == 587,
                            )
                            try {
                                selfTestMode = sendSelfTestWithFallback(
                                    sender = sender,
                                    recipientEmail = recipientEmail,
                                    hasAppPassword = appPassword.isNotBlank(),
                                )
                                break  // успех — выходим из цикла портов
                            } catch (e: Throwable) {
                                if (isAuthError(e)) throw e  // auth-ошибку не повторяем
                                lastEndpointError = e
                                android.util.Log.w("SmtpSelfTest", "Port ${endpoint.port} failed: ${e.message}, trying next")
                            }
                        }
                        if (selfTestMode == null) throw lastEndpointError ?: IllegalStateException("No SMTP endpoints connected")
                        val mode = selfTestMode
                        if (smtpIdentity != resolvedSession.smtpIdentity) {
                            yandexSecureStore.saveSession(
                                token = resolvedSession.token,
                                email = smtpIdentity,
                                login = resolvedSession.login,
                                userId = resolvedSession.userId,
                            )
                        }
                        return@withContext SelfTestExecutionResult(
                            authMode = if (mode == SmtpAuthMode.APP_PASSWORD) {
                                "app_password"
                            } else {
                                "oauth2"
                            },
                            recipientEmail = recipientEmail,
                        )
                    }
                    if (lastAuthError != null) {
                        throw lastAuthError
                    }
                    throw SmtpIdentityMissingException()
                }
            }.onSuccess { outcome ->
                yandexSecureStore.setSmtpReady(true)
                result.success(
                    mapOf(
                        "success" to true,
                        "authMode" to outcome.authMode,
                        "recipientEmail" to outcome.recipientEmail,
                        "message" to "Тестовое письмо отправлено",
                    ),
                )
            }.onFailure { error ->
                yandexSecureStore.setSmtpReady(false)
                when {
                    error is SmtpIdentityMissingException -> {
                        result.error(
                            "smtp_identity_missing",
                            "Не удалось получить адрес отправителя из Яндекса. Войдите заново и повторите проверку отправки.",
                            null,
                        )
                    }

                    error is YandexUserInfoApi.UnauthorizedException -> {
                        result.error(
                            "unauthorized",
                            "Сессия Яндекса устарела. Войдите снова.",
                            null,
                        )
                    }

                    isAuthError(error) -> {
                        result.error(
                            "smtp_auth_failed",
                            "Не удалось войти в SMTP Яндекса. Для этого аккаунта доступ к SMTP запрещён или нужен пароль приложения.",
                            mapOf("serverMessage" to (error.message ?: error.cause?.message ?: "")),
                        )
                    }

                    isNetworkError(error) -> {
                        result.error(
                            "network_error",
                            "Нет интернета. Повторите попытку позже.",
                            null,
                        )
                    }

                    else -> {
                        result.error(
                            "smtp_test_failed",
                            "Тест отправки не выполнен. Повторите попытку.",
                            null,
                        )
                    }
                }
            }
        }
    }

    @Throws(Throwable::class)
    private fun ensureSmtpIdentity(session: YandexAuthSession): YandexAuthSession {
        if (session.smtpIdentity.isNotBlank()) {
            return session
        }

        val profile = userInfoApi.loadProfile(session.token)
        yandexSecureStore.saveSession(
            token = session.token,
            email = profile.bestEmailOrNull().orEmpty(),
            login = profile.login,
            userId = profile.id,
        )
        val refreshed = yandexSecureStore.loadSession() ?: throw SmtpIdentityMissingException()
        if (refreshed.smtpIdentity.isBlank()) {
            throw SmtpIdentityMissingException()
        }
        return refreshed
    }

    private class SmtpIdentityMissingException : IllegalStateException()

    private data class SelfTestExecutionResult(
        val authMode: String,
        val recipientEmail: String,
    )

    private fun buildSmtpIdentityCandidates(session: YandexAuthSession): List<String> {
        val primary = session.smtpIdentity.trim()
        if (primary.isBlank()) {
            return emptyList()
        }
        if (!Patterns.EMAIL_ADDRESS.matcher(primary).matches()) {
            return emptyList()
        }
        return listOf(primary)
    }

    private fun sendSelfTestWithFallback(
        sender: SmtpSender,
        recipientEmail: String,
        hasAppPassword: Boolean,
    ): SmtpAuthMode {
        return try {
            sender.send(
                recipientEmail = recipientEmail,
                subject = "Тест отправки ФотоПочта",
                bodyText = "Это тестовое письмо. Отправка из ФотоПочта настроена корректно.",
                attachments = emptyList(),
                authMode = SmtpAuthMode.OAUTH2,
            )
            SmtpAuthMode.OAUTH2
        } catch (oauthError: Throwable) {
            if (!isAuthError(oauthError) || !hasAppPassword) {
                throw oauthError
            }
            Log.w("SmtpSelfTest", "OAuth2 failed (${oauthError.message}), trying App Password")
            sender.send(
                recipientEmail = recipientEmail,
                subject = "Тест отправки ФотоПочта",
                bodyText = "Это тестовое письмо. Отправка из ФотоПочта настроена корректно.",
                attachments = emptyList(),
                authMode = SmtpAuthMode.APP_PASSWORD,
            )
            SmtpAuthMode.APP_PASSWORD
        }
    }

    private fun normalizeSmtpAppPassword(raw: String): String =
        SmtpUtils.normalizeAppPassword(raw)

    private fun isValidSmtpAppPassword(value: String): Boolean =
        SmtpUtils.isValidAppPassword(value)


    private fun isAuthError(error: Throwable): Boolean {
        if (error is AuthenticationFailedException) {
            return true
        }
        if (error is MessagingException) {
            if (error.nextException is AuthenticationFailedException) {
                return true
            }
            if (error.cause is AuthenticationFailedException) {
                return true
            }
        }
        val lower = (error.message ?: "").lowercase()
        return lower.contains("auth") ||
            lower.contains("oauth") ||
            lower.contains("token") ||
            lower.contains("535") ||
            lower.contains("5.7.8")
    }

    private fun isNetworkError(error: Throwable): Boolean {
        return error is SocketTimeoutException ||
            error is ConnectException ||
            error is UnknownHostException ||
            error is IOException
    }

    private fun jobStatusMap(job: JobEntity): Map<String, Any?> {
        return mapOf(
            "jobId" to job.jobId,
            "state" to job.state,
            "sentBatches" to job.sentBatches,
            "totalBatches" to job.totalBatches,
            "lastError" to job.lastError,
            "updatedAt" to job.updatedAt,
        )
    }

    private fun parseRequest(call: MethodCall): SendJobRequest? {
        val recipientEmail = call.argument<String>("recipientEmail")?.trim().orEmpty()
        val subjectInput = call.argument<String>("subjectInput")?.trim().orEmpty()
        val limitBytes = call.argument<Number>("limitBytes")?.toLong() ?: -1L
        val compressionPreset = call.argument<String>("compressionPreset")
            ?.trim()
            ?.lowercase()
            .orEmpty()
            .ifBlank { "none" }
        val photos = parseSendPhotos(call)
        if (recipientEmail.isBlank()) {
            return null
        }
        return SendJobRequest(
            recipientEmail = recipientEmail,
            subjectInput = subjectInput,
            limitBytes = limitBytes,
            compressionPreset = compressionPreset,
            photos = photos,
        )
    }

    private fun parseSendPhotos(call: MethodCall): List<SendPhoto> {
        val rawPhotos = call.argument<List<*>>("photos").orEmpty()
        return rawPhotos.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val uri = map["uri"]?.toString()?.trim().orEmpty()
            if (uri.isBlank()) {
                return@mapNotNull null
            }
            SendPhoto(
                uri = uri,
                name = map["name"]?.toString().orEmpty().ifBlank { "file" },
                sizeBytes = (map["sizeBytes"] as? Number)?.toLong() ?: 0L,
                mimeType = map["mimeType"]?.toString()?.trim(),
            )
        }
    }

    private data class SendJobRequest(
        val recipientEmail: String,
        val subjectInput: String,
        val limitBytes: Long,
        val compressionPreset: String,
        val photos: List<SendPhoto>,
    )

    private data class SendPhoto(
        val uri: String,
        val name: String,
        val sizeBytes: Long,
        val mimeType: String?,
    )

    companion object {
        private const val CHANNEL_NAME = "ru.amajo.photomailer/native"
        private const val REQUEST_CODE_YANDEX_AUTH = 9107

        private const val METHOD_PICK_PHOTOS = "pickPhotos"
        private const val METHOD_SAVE_APP_PATTERN = "saveAppPattern"
        private const val METHOD_VERIFY_APP_PATTERN = "verifyAppPattern"
        private const val METHOD_HAS_APP_PATTERN = "hasAppPattern"
        private const val METHOD_CLEAR_APP_PATTERN = "clearAppPattern"
        private const val METHOD_OPEN_EXTERNAL_EMAIL = "openExternalEmail"
        private const val METHOD_GET_YANDEX_AUTH_STATE = "getYandexAuthState"
        private const val METHOD_START_YANDEX_LOGIN = "startYandexLogin"
        private const val METHOD_LOGOUT_YANDEX = "logoutYandex"
        private const val METHOD_GET_ACCESSIBILITY_STATE = "getAccessibilityState"
        private const val METHOD_OPEN_ACCESSIBILITY_SETTINGS = "openAccessibilitySettings"
        private const val METHOD_START_SHARE_AUTOMATION_SERIES = "startShareAutomationSeries"
        private const val METHOD_GET_SHARE_AUTOMATION_STATE = "getShareAutomationState"
        private const val METHOD_RESUME_SHARE_AUTOMATION = "resumeShareAutomation"
        private const val METHOD_CANCEL_SHARE_AUTOMATION = "cancelShareAutomation"
        private const val METHOD_OPEN_CURRENT_SHARE_BATCH_MANUALLY =
            "openCurrentShareBatchManually"
        private const val METHOD_ENQUEUE_SEND_JOB = "enqueueSendJob"
        private const val METHOD_GET_JOB_STATUS = "getJobStatus"
        private const val METHOD_GET_JOB_LOGS = "getJobLogs"
        private const val METHOD_CANCEL_SEND_JOB = "cancelSendJob"
        private const val METHOD_GET_LATEST_JOB_STATUS = "getLatestJobStatus"
        private const val METHOD_RUN_SMTP_SELF_TEST = "runSmtpSelfTest"
        private const val METHOD_SAVE_AND_RUN_SMTP_SELF_TEST = "saveAndRunSmtpSelfTest"
        private const val METHOD_SAVE_SMTP_APP_PASSWORD = "saveSmtpAppPassword"
        private const val METHOD_HAS_SMTP_APP_PASSWORD = "hasSmtpAppPassword"
        private const val METHOD_CLEAR_SMTP_APP_PASSWORD = "clearSmtpAppPassword"
        // MIN_PASSWORD_LENGTH перенесён в SmtpUtils
    }
}
