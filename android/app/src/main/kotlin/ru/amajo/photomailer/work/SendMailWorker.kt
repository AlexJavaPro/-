package ru.amajo.photomailer.work

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Locale
import jakarta.mail.AuthenticationFailedException
import jakarta.mail.MessagingException
import ru.amajo.photomailer.R
import ru.amajo.photomailer.auth.AuthActivity
import ru.amajo.photomailer.db.AppDatabase
import ru.amajo.photomailer.db.JobState
import ru.amajo.photomailer.db.LogEntity
import ru.amajo.photomailer.files.AttachmentPreparer
import ru.amajo.photomailer.files.AttachmentPreparer.CompressionMode
import ru.amajo.photomailer.files.PreparedAttachment
import ru.amajo.photomailer.mail.MimeResolver
import ru.amajo.photomailer.mail.OutgoingAttachment
import ru.amajo.photomailer.mail.SmtpAuthMode
import ru.amajo.photomailer.mail.SmtpProviderResolver
import ru.amajo.photomailer.mail.SmtpEndpoint
import ru.amajo.photomailer.mail.SmtpSender
import ru.amajo.photomailer.mail.SmtpUtils
import ru.amajo.photomailer.security.SecurePasswordStore
import ru.amajo.photomailer.security.YandexSecureStore
import ru.amajo.photomailer.split.BatchSplitter

class SendMailWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    private val database = AppDatabase.getInstance(appContext)
    private val jobDao = database.jobDao()
    private val photoDao = database.photoDao()
    private val logDao = database.logDao()

    override suspend fun doWork(): Result {
        val jobId = inputData.getString(SendWorkScheduler.KEY_JOB_ID) ?: return Result.failure()
        val authStore = YandexSecureStore(applicationContext)
        val appPasswordStore = SecurePasswordStore(applicationContext)
        AttachmentPreparer.clearTempCache(applicationContext)
        val compressionPreset = inputData.getString(SendWorkScheduler.KEY_COMPRESSION_PRESET)
            ?.trim()
            ?.lowercase()
            .orEmpty()
            .ifBlank { "none" }

        val job = jobDao.findById(jobId) ?: return Result.failure()
        val photos = photoDao.listByJob(jobId)
        if (photos.isEmpty()) {
            markFailed(jobId, "Нет файлов для отправки")
            AttachmentPreparer.clearTempCache(applicationContext)
            return Result.failure()
        }

        val authSession = authStore.loadSession()
        if (authSession == null) {
            markFailed(jobId, "Сессия Яндекса отсутствует")
            postCompletionNotification(
                jobId = jobId,
                title = applicationContext.getString(R.string.sending_notification_title),
                message = "Сессия Яндекса не найдена. Выполните вход заново.",
                success = false,
                pendingIntent = buildAuthPendingIntent(),
            )
            AttachmentPreparer.clearTempCache(applicationContext)
            return Result.failure()
        }
        if (authSession.smtpIdentity.isBlank()) {
            markFailed(jobId, "Не удалось определить адрес отправителя")
            postCompletionNotification(
                jobId = jobId,
                title = applicationContext.getString(R.string.sending_notification_title),
                message = "Не удалось определить адрес отправителя. Проверьте вход в Яндекс и тест отправки.",
                success = false,
                pendingIntent = buildAuthPendingIntent(),
            )
            AttachmentPreparer.clearTempCache(applicationContext)
            return Result.failure()
        }

        return try {
            jobDao.updateState(jobId, JobState.RUNNING, now(), null)
            appendLog(jobId, "INFO", "Подготовка вложений: файлов ${photos.size}", null)

            val batches = BatchSplitter.split(photos, job.limitBytes) { it.sizeBytes }
            jobDao.updateProgress(jobId, batches.size, 0, now())
            setForeground(createForegroundInfo("Подготовка вложений", 0, batches.size))

            val mimeResolver = MimeResolver(applicationContext)
            val attachmentPreparer = AttachmentPreparer(
                context = applicationContext,
                mimeResolver = mimeResolver,
                compressionPreset = compressionPreset,
                maxAttachmentBytes = job.limitBytes,
                compressionMode = CompressionMode.OVERSIZED_ONLY,
            )
            val smtpEndpoints = SmtpProviderResolver.resolveOrderedBySenderEmail(job.senderEmail)
            appendLog(
                jobId = jobId,
                level = "INFO",
                message = "SMTP endpoints: ${smtpEndpoints.joinToString { "${it.host}:${it.port}" }}",
                batchIndex = null,
            )

            val appPassword = SmtpUtils.normalizeAppPassword(appPasswordStore.loadPassword().orEmpty())
            val smtpEndpoint = smtpEndpoints.first()
            val smtpSender = SmtpSender(
                senderEmail = authSession.smtpIdentity,
                smtpHost = smtpEndpoint.host,
                smtpPort = smtpEndpoint.port,
                oauthToken = authSession.token,
                appPassword = appPassword,
                useStartTls = smtpEndpoint.port == 587,
            )

            val subjectBase = job.subjectInput.trim().ifBlank { "Фото" }
            val totalFiles = photos.size
            var sentFiles = 0

            for ((index, batch) in batches.withIndex()) {
                if (isStopped) {
                    jobDao.updateState(jobId, JobState.CANCELLED, now(), "Отправка остановлена системой")
                    appendLog(jobId, "WARN", "Отправка остановлена системой", null)
                    AttachmentPreparer.clearTempCache(applicationContext)
                    postCompletionNotification(
                        jobId = jobId,
                        title = applicationContext.getString(R.string.sending_notification_title),
                        message = "Отправка остановлена",
                        success = false,
                    )
                    return Result.failure()
                }

                val batchNumber = index + 1
                val subject = "$subjectBase ($batchNumber/${batches.size})"

                setForeground(
                    createForegroundInfo(
                        text = "Сжатие (если нужно) $batchNumber/${batches.size}",
                        sent = index,
                        total = batches.size,
                    ),
                )
                appendLog(
                    jobId = jobId,
                    level = "INFO",
                    message = "Сжатие (если нужно): письмо $batchNumber/${batches.size}",
                    batchIndex = batchNumber,
                )

                val attachments = attachmentPreparer.copyBatch(batch)
                val oversized = attachments.filter { it.exceedsLimit }
                if (oversized.isNotEmpty()) {
                    appendLog(
                        jobId = jobId,
                        level = "WARN",
                        message = "Не удалось снизить размер до лимита для ${oversized.size} фото",
                        batchIndex = batchNumber,
                    )
                }
                val bodyText = buildBodyText(
                    batchNumber = batchNumber,
                    totalBatches = batches.size,
                    attachments = attachments,
                )

                try {
                    setForeground(
                        createForegroundInfo(
                            text = "Отправка письма $batchNumber/${batches.size}",
                            sent = index,
                            total = batches.size,
                        ),
                    )
                    appendLog(
                        jobId = jobId,
                        level = "INFO",
                        message = "Отправка письма $batchNumber/${batches.size}",
                        batchIndex = batchNumber,
                    )

                    val outgoingAttachments = attachments.map {
                        OutgoingAttachment(
                            file = it.file,
                            displayName = it.displayName,
                            mimeType = it.mimeType,
                        )
                    }
                    val usedAuthMode = sendWithAuthFallback(
                        sender = smtpSender,
                        recipientEmail = job.recipientEmail,
                        subject = subject,
                        bodyText = bodyText,
                        attachments = outgoingAttachments,
                        hasAppPassword = appPassword.isNotBlank(),
                    )
                    appendLog(
                        jobId = jobId,
                        level = "INFO",
                        message = if (usedAuthMode == SmtpAuthMode.APP_PASSWORD) {
                            "SMTP авторизация: пароль приложения"
                        } else {
                            "SMTP авторизация: OAuth2"
                        },
                        batchIndex = batchNumber,
                    )
                } finally {
                    attachmentPreparer.cleanup(attachments)
                }

                jobDao.updateSentBatches(jobId, batchNumber, now())
                sentFiles += batch.size
                appendLog(jobId, "INFO", "Отправлено файлов: $sentFiles из $totalFiles", batchNumber)
            }

            jobDao.updateState(jobId, JobState.SUCCEEDED, now(), null)
            appendLog(jobId, "INFO", "Отправка завершена успешно", null)
            AttachmentPreparer.clearTempCache(applicationContext)
            postCompletionNotification(
                jobId = jobId,
                title = applicationContext.getString(R.string.sending_notification_title),
                message = applicationContext.getString(R.string.sending_result_success),
                success = true,
            )
            Result.success()
        } catch (error: Throwable) {
            val result = handleError(jobId, error, authStore)
            AttachmentPreparer.clearTempCache(applicationContext)
            result
        }
    }

    private fun buildBodyText(
        batchNumber: Int,
        totalBatches: Int,
        attachments: List<PreparedAttachment>,
    ): String {
        val totalBytes = attachments.fold(0L) { sum, item -> sum + item.sizeBytes.coerceAtLeast(0L) }
        val filesList = attachments
            .mapIndexed { index, item ->
                "${index + 1}. ${item.displayName} (${formatBytes(item.sizeBytes)})"
            }
            .joinToString(separator = "\n")

        return buildString {
            append("Здравствуйте!\n\n")
            append("Файлы в этом письме ($batchNumber/$totalBatches):\n")
            append(filesList)
            append("\n\n")
            append("Общий размер письма: ${formatBytes(totalBytes)}\n")
            append("Отправлено через ФотоПочта.\n")
        }
    }

    private fun formatBytes(bytes: Long): String {
        val normalized = bytes.coerceAtLeast(0L)
        val kb = 1024.0
        val mb = kb * 1024.0

        return when {
            normalized >= mb -> String.format(Locale.US, "%.2f МБ", normalized / mb)
            normalized >= kb -> String.format(Locale.US, "%.1f КБ", normalized / kb)
            else -> "$normalized Б"
        }
    }

    private suspend fun handleError(
        jobId: String,
        error: Throwable,
        authStore: YandexSecureStore,
    ): Result {
        val technicalMessage = error.message ?: error.javaClass.simpleName
        val userMessage = toUserFacingError(error)
        if (isAuthenticationError(error)) {
            val tokenExpired = isExpiredTokenError(error)
            markFailed(jobId, userMessage)
            appendLog(
                jobId = jobId,
                level = "DEBUG",
                message = "SMTP auth details: $technicalMessage",
                batchIndex = null,
            )
            if (tokenExpired) {
                authStore.clearSession()
            }
            postCompletionNotification(
                jobId = jobId,
                title = applicationContext.getString(R.string.sending_notification_title),
                message = if (tokenExpired) {
                    "Сессия Яндекса устарела. Войдите снова."
                } else {
                    userMessage
                },
                success = false,
                pendingIntent = if (tokenExpired) buildAuthPendingIntent() else null,
            )
            return Result.failure()
        }

        val shouldRetry = isRetryable(error) && runAttemptCount < MAX_RETRIES
        if (shouldRetry) {
            jobDao.updateState(jobId, JobState.RETRYING, now(), userMessage)
            appendLog(jobId, "WARN", "Повторная попытка после ошибки: $userMessage", null)
            appendLog(
                jobId = jobId,
                level = "DEBUG",
                message = "Retry details: $technicalMessage",
                batchIndex = null,
            )
            return Result.retry()
        }
        markFailed(jobId, userMessage)
        appendLog(
            jobId = jobId,
            level = "DEBUG",
            message = "Failure details: $technicalMessage",
            batchIndex = null,
        )
        postCompletionNotification(
            jobId = jobId,
            title = applicationContext.getString(R.string.sending_notification_title),
            message = applicationContext.getString(R.string.sending_result_error, userMessage),
            success = false,
        )
        return Result.failure()
    }

    private fun toUserFacingError(error: Throwable): String {
        if (isAuthenticationError(error)) {
            return if (isExpiredTokenError(error)) {
                "Сессия Яндекса устарела. Войдите снова."
            } else if (isSmtpNoAccessError(error)) {
                "Не удалось войти в SMTP Яндекса. Для этого аккаунта доступ к SMTP запрещён или нужен пароль приложения."
            } else {
                "Неверный логин или пароль SMTP."
            }
        }
        if (isRetryable(error)) {
            return "Сетевая ошибка. Попробуйте позже."
        }
        val raw = error.message?.trim().orEmpty()
        if (raw.isEmpty()) {
            return "Произошла ошибка отправки."
        }
        return if (raw.length > 220) {
            raw.take(220)
        } else {
            raw
        }
    }

    private fun sendWithAuthFallback(
        sender: SmtpSender,
        recipientEmail: String,
        subject: String,
        bodyText: String,
        attachments: List<OutgoingAttachment>,
        hasAppPassword: Boolean,
    ): SmtpAuthMode {
        return try {
            sender.send(
                recipientEmail = recipientEmail,
                subject = subject,
                bodyText = bodyText,
                attachments = attachments,
                authMode = SmtpAuthMode.OAUTH2,
            )
            SmtpAuthMode.OAUTH2
        } catch (oauthError: Throwable) {
            if (!isAuthenticationError(oauthError) || !hasAppPassword) {
                throw oauthError
            }
            sender.send(
                recipientEmail = recipientEmail,
                subject = subject,
                bodyText = bodyText,
                attachments = attachments,
                authMode = SmtpAuthMode.APP_PASSWORD,
            )
            SmtpAuthMode.APP_PASSWORD
        }
    }

    /**
     * Перебирает SMTP endpoint-ы (465→587) при сетевой ошибке.
     * При каждом endpoint вызывает sendWithAuthFallback.
     */
    private fun sendWithEndpointFallback(
        endpointsOrdered: List<SmtpEndpoint>,
        authSession: ru.amajo.photomailer.security.YandexAuthSession,
        appPassword: String,
        recipientEmail: String,
        subject: String,
        bodyText: String,
        attachments: List<OutgoingAttachment>,
    ): SmtpAuthMode {
        var lastError: Throwable? = null
        for (endpoint in endpointsOrdered) {
            try {
                val sender = SmtpSender(
                    senderEmail = authSession.smtpIdentity,
                    smtpHost = endpoint.host,
                    smtpPort = endpoint.port,
                    oauthToken = authSession.token,
                    appPassword = appPassword,
                    useStartTls = endpoint.port == 587,
                )
                return sendWithAuthFallback(
                    sender = sender,
                    recipientEmail = recipientEmail,
                    subject = subject,
                    bodyText = bodyText,
                    attachments = attachments,
                    hasAppPassword = appPassword.isNotBlank(),
                )
            } catch (e: Throwable) {
                if (isAuthenticationError(e)) throw e  // не пробуем другой порт при auth-ошибке
                lastError = e
                android.util.Log.w("SendMailWorker", "SMTP ${endpoint.host}:${endpoint.port} failed: ${e.message}, trying next endpoint")
            }
        }
        throw lastError ?: IllegalStateException("No SMTP endpoints available")
    }

    private suspend fun markFailed(jobId: String, message: String) {
        jobDao.updateState(jobId, JobState.FAILED, now(), message)
        appendLog(jobId, "ERROR", message, null)
    }

    private suspend fun appendLog(
        jobId: String,
        level: String,
        message: String,
        batchIndex: Int?,
    ) {
        logDao.insert(
            LogEntity(
                jobId = jobId,
                level = level,
                message = message,
                batchIndex = batchIndex,
                createdAt = now(),
            ),
        )
    }

    private fun isRetryable(error: Throwable): Boolean {
        if (error is AuthenticationFailedException) {
            return false
        }
        if (
            error is SocketTimeoutException ||
            error is ConnectException ||
            error is UnknownHostException ||
            error is IOException
        ) {
            return true
        }
        if (error is MessagingException) {
            val nested = error.nextException ?: error.cause
            return nested is IOException
        }
        return false
    }

    private fun isAuthenticationError(error: Throwable): Boolean {
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
        // Ряд серверов возвращает MessagingException с текстом "535" или "5.7.8"
        // без вложенного AuthenticationFailedException — ловим и такие случаи.
        val lower = buildString {
            append(error.message.orEmpty())
            if (error is MessagingException) {
                append(" ").append(error.nextException?.message.orEmpty())
                append(" ").append(error.cause?.message.orEmpty())
            } else {
                append(" ").append(error.cause?.message.orEmpty())
            }
        }.lowercase()
        return lower.contains("535") ||
            lower.contains("5.7.8") ||
            lower.contains("authentication failed") ||
            lower.contains("invalid credentials")
    }

    private fun isExpiredTokenError(error: Throwable): Boolean {
        val lower = buildString {
            append(error.message.orEmpty())
            if (error is MessagingException) {
                append(" ")
                append(error.nextException?.message.orEmpty())
                append(" ")
                append(error.cause?.message.orEmpty())
            } else {
                append(" ")
                append(error.cause?.message.orEmpty())
            }
        }.lowercase()

        return lower.contains("token expired") ||
            lower.contains("expired token") ||
            lower.contains("token has expired") ||
            lower.contains("invalid token") ||
            lower.contains("invalid_grant") ||
            lower.contains("oauth token is invalid") ||
            lower.contains(" 401")
    }


    private fun isSmtpNoAccessError(error: Throwable): Boolean {
        val lower = buildString {
            append(error.message.orEmpty())
            if (error is MessagingException) {
                append(" ")
                append(error.nextException?.message.orEmpty())
                append(" ")
                append(error.cause?.message.orEmpty())
            } else {
                append(" ")
                append(error.cause?.message.orEmpty())
            }
        }.lowercase()

        return lower.contains("5.7.8") ||
            lower.contains("this user does not have access rights to this service") ||
            lower.contains("доступ к smtp запрещ")
    }

    private fun createForegroundInfo(
        text: String,
        sent: Int,
        total: Int,
    ): ForegroundInfo {
        ensureNotificationChannels()
        val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID_PROGRESS)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(applicationContext.getString(R.string.sending_notification_title))
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (total > 0) {
            builder.setProgress(total, sent, false)
        } else {
            builder.setProgress(0, 0, true)
        }

        val notification = builder.build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID_PROGRESS,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID_PROGRESS, notification)
        }
    }

    private fun ensureNotificationChannels() {
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (manager.getNotificationChannel(CHANNEL_ID_PROGRESS) == null) {
            val progressChannel = NotificationChannel(
                CHANNEL_ID_PROGRESS,
                applicationContext.getString(R.string.sending_notification_channel),
                NotificationManager.IMPORTANCE_LOW,
            )
            manager.createNotificationChannel(progressChannel)
        }

        if (manager.getNotificationChannel(CHANNEL_ID_RESULT) == null) {
            val resultChannel = NotificationChannel(
                CHANNEL_ID_RESULT,
                applicationContext.getString(R.string.sending_result_notification_channel),
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            manager.createNotificationChannel(resultChannel)
        }
    }

    private fun postCompletionNotification(
        jobId: String,
        title: String,
        message: String,
        success: Boolean,
        pendingIntent: PendingIntent? = null,
    ) {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ContextCompat.checkSelfPermission(
                    applicationContext,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    return@runCatching
                }
            }

            ensureNotificationChannels()
            val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val icon = if (success) {
                android.R.drawable.stat_sys_upload_done
            } else {
                android.R.drawable.stat_notify_error
            }
            val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID_RESULT)
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setAutoCancel(true)
                .setOngoing(false)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .apply {
                    if (pendingIntent != null) {
                        setContentIntent(pendingIntent)
                    }
                }
                .build()

            val notificationId = NOTIFICATION_ID_RESULT_BASE + (jobId.hashCode() and 0x3FF)
            manager.notify(notificationId, notification)
        }
    }

    private fun buildAuthPendingIntent(): PendingIntent {
        val intent = AuthActivity.createIntent(applicationContext).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(
            applicationContext,
            AUTH_REQUEST_CODE,
            intent,
            flags,
        )
    }

    private fun now(): Long = System.currentTimeMillis()

    companion object {
        private const val CHANNEL_ID_PROGRESS = "photo_mailer_send"
        private const val CHANNEL_ID_RESULT = "photo_mailer_send_result"
        private const val NOTIFICATION_ID_PROGRESS = 1010
        private const val NOTIFICATION_ID_RESULT_BASE = 3000
        private const val AUTH_REQUEST_CODE = 5007
        private const val MAX_RETRIES = 3
    }
}

