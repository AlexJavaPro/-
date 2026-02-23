package ru.amajo.photomailer.automation

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import ru.amajo.photomailer.R
import ru.amajo.photomailer.accessibility.YandexMailAccessibilityService

class ShareAutomationForegroundService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var orchestrator: ShareAutomationOrchestrator
    private lateinit var progressStore: SendProgressStore

    override fun onCreate() {
        super.onCreate()
        progressStore = SendProgressStore(applicationContext)
        orchestrator = ShareAutomationOrchestrator(applicationContext, progressStore)
        ensureNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Подготовка автоматической отправки"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startSeries(intent)
            ACTION_RESUME -> resumeSeries()
            ACTION_CANCEL -> cancelSeries()
            ACTION_OPEN_MANUAL -> openCurrentBatchManually()
        }
        return START_STICKY
    }

    private fun startSeries(intent: Intent) {
        val recipient = intent.getStringExtra(EXTRA_RECIPIENT).orEmpty()
        val subject = intent.getStringExtra(EXTRA_SUBJECT).orEmpty()
        val limitBytes = intent.getLongExtra(EXTRA_LIMIT_BYTES, 25L * 1024L * 1024L)
        val photos = parsePhotosJson(intent.getStringExtra(EXTRA_PHOTOS_JSON))

        if (recipient.isBlank() || photos.isEmpty()) {
            updateState(
                ShareAutomationSession.idle().copy(
                    status = ShareAutomationStatus.FAILED,
                    lastError = "Некорректные данные для запуска автосерии",
                    updatedAt = System.currentTimeMillis(),
                ),
            )
            stopSelf()
            return
        }

        val session = orchestrator.buildSession(
            recipientEmail = recipient,
            subjectBase = subject,
            targetPackage = TARGET_PACKAGE,
            limitBytes = limitBytes,
            photos = photos,
        )
        runOrchestrator(session)
    }

    private fun parsePhotosJson(raw: String?): List<ShareAutomationPhoto> {
        val payload = raw?.trim().orEmpty()
        if (payload.isEmpty()) {
            return emptyList()
        }
        return runCatching {
            val array = JSONArray(payload)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val uri = item.optString("uri", "").trim()
                    if (uri.isEmpty()) {
                        continue
                    }
                    add(
                        ShareAutomationPhoto(
                            uri = uri,
                            name = item.optString("name", "file"),
                            sizeBytes = item.optLong("sizeBytes", 0L),
                            mimeType = item.optString("mimeType").ifBlank { null },
                        ),
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun resumeSeries() {
        val session = orchestrator.resumeSession()
        if (session == null || session.status == ShareAutomationStatus.IDLE) {
            stopSelf()
            return
        }
        runOrchestrator(
            session.copy(
                status = ShareAutomationStatus.PRECHECK,
                updatedAt = System.currentTimeMillis(),
            ),
        )
    }

    private fun cancelSeries() {
        orchestrator.clear()
        updateState(
            ShareAutomationSession.idle().copy(
                status = ShareAutomationStatus.CANCELLED,
                lastError = null,
                updatedAt = System.currentTimeMillis(),
            ),
        )
        stopSelf()
    }

    private fun openCurrentBatchManually() {
        val opened = orchestrator.openCurrentBatchManually()
        val current = progressStore.load() ?: ShareAutomationSession.idle()
        val updated = current.copy(
            status = if (opened) {
                ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED
            } else {
                ShareAutomationStatus.FAILED
            },
            lastError = if (opened) {
                "Текущий пакет открыт вручную"
            } else {
                "Не удалось открыть текущий пакет вручную"
            },
            updatedAt = System.currentTimeMillis(),
        )
        updateState(updated)
        if (!opened) {
            stopSelf()
        }
    }

    private fun runOrchestrator(session: ShareAutomationSession) {
        scope.launch {
            updateState(
                session.copy(
                    status = ShareAutomationStatus.PRECHECK,
                    updatedAt = System.currentTimeMillis(),
                ),
            )
            if (!YandexMailAccessibilityService.isEnabled(applicationContext)) {
                val paused = session.copy(
                    status = ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED,
                    lastError = "Включите сервис доступности для автоматической отправки",
                    updatedAt = System.currentTimeMillis(),
                )
                updateState(paused)
                stopSelf()
                return@launch
            }

            val result = orchestrator.run(session)
            updateState(result)
            if (
                result.status == ShareAutomationStatus.COMPLETED ||
                result.status == ShareAutomationStatus.FAILED ||
                result.status == ShareAutomationStatus.CANCELLED ||
                result.status == ShareAutomationStatus.AUTH_RELOGIN_REQUIRED ||
                result.status == ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED
            ) {
                stopSelf()
            }
        }
    }

    private fun updateState(session: ShareAutomationSession) {
        progressStore.save(session)
        val text = when (session.status) {
            ShareAutomationStatus.COMPLETED -> "Серия отправлена"
            ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED -> "Пауза: требуется действие"
            ShareAutomationStatus.AUTH_RELOGIN_REQUIRED -> "Требуется повторный вход"
            ShareAutomationStatus.FAILED -> "Ошибка автоматизации"
            ShareAutomationStatus.CANCELLED -> "Серия отменена"
            else -> {
                val current = (session.currentBatchIndex + 1).coerceAtLeast(1)
                "Пакет $current из ${session.totalBatches}"
            }
        }
        val notification = buildNotification(text)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(text: String) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(getString(R.string.sending_notification_title))
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun ensureNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.share_automation_channel),
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "photo_mailer_share_automation"
        private const val NOTIFICATION_ID = 1060
        private const val TARGET_PACKAGE = "ru.yandex.mail"

        private const val ACTION_START = "ru.amajo.photomailer.automation.START"
        private const val ACTION_RESUME = "ru.amajo.photomailer.automation.RESUME"
        private const val ACTION_CANCEL = "ru.amajo.photomailer.automation.CANCEL"
        private const val ACTION_OPEN_MANUAL = "ru.amajo.photomailer.automation.OPEN_MANUAL"

        private const val EXTRA_RECIPIENT = "extra_recipient"
        private const val EXTRA_SUBJECT = "extra_subject"
        private const val EXTRA_LIMIT_BYTES = "extra_limit_bytes"
        private const val EXTRA_PHOTOS_JSON = "extra_photos_json"

        fun startSeries(
            context: Context,
            recipientEmail: String,
            subjectInput: String,
            limitBytes: Long,
            photos: List<Map<String, Any?>>,
        ) {
            val photosJson = JSONArray().apply {
                photos.forEach { photo ->
                    val item = JSONObject()
                    item.put("uri", photo["uri"]?.toString().orEmpty())
                    item.put("name", photo["name"]?.toString().orEmpty())
                    item.put("sizeBytes", (photo["sizeBytes"] as? Number)?.toLong() ?: 0L)
                    item.put("mimeType", photo["mimeType"]?.toString())
                    put(item)
                }
            }.toString()

            val intent = Intent(context, ShareAutomationForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RECIPIENT, recipientEmail)
                putExtra(EXTRA_SUBJECT, subjectInput)
                putExtra(EXTRA_LIMIT_BYTES, limitBytes)
                putExtra(EXTRA_PHOTOS_JSON, photosJson)
            }
            context.startForegroundService(intent)
        }

        fun resume(context: Context) {
            val intent = Intent(context, ShareAutomationForegroundService::class.java).apply {
                action = ACTION_RESUME
            }
            context.startForegroundService(intent)
        }

        fun cancel(context: Context) {
            val intent = Intent(context, ShareAutomationForegroundService::class.java).apply {
                action = ACTION_CANCEL
            }
            context.startService(intent)
        }

        fun openCurrentBatchManually(context: Context) {
            val intent = Intent(context, ShareAutomationForegroundService::class.java).apply {
                action = ACTION_OPEN_MANUAL
            }
            context.startForegroundService(intent)
        }

        fun getState(context: Context): ShareAutomationSession {
            return SendProgressStore(context).load() ?: ShareAutomationSession.idle()
        }
    }
}

