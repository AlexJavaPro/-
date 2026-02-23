package ru.amajo.photomailer.automation

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import ru.amajo.photomailer.accessibility.YandexMailAccessibilityService
import ru.amajo.photomailer.security.YandexSecureStore
import java.util.UUID

class ShareAutomationOrchestrator(
    private val appContext: Context,
    private val progressStore: SendProgressStore,
) {
    suspend fun run(session: ShareAutomationSession): ShareAutomationSession {
        var current = session.copy(
            status = ShareAutomationStatus.PRECHECK,
            updatedAt = now(),
            lastError = null,
        )
        save(current)

        if (!YandexMailAccessibilityService.isEnabled(appContext)) {
            current = current.copy(
                status = ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED,
                lastError = "Сервис доступности выключен",
                updatedAt = now(),
            )
            save(current)
            return current
        }

        val auth = YandexSecureStore(appContext).loadSession()
        if (auth == null) {
            current = current.copy(
                status = ShareAutomationStatus.AUTH_RELOGIN_REQUIRED,
                lastError = "Токен Яндекса отсутствует",
                updatedAt = now(),
            )
            save(current)
            return current
        }

        while (current.currentBatchIndex < current.totalBatches) {
            val batch = current.batches.getOrNull(current.currentBatchIndex)
            if (batch == null) {
                current = current.copy(
                    status = ShareAutomationStatus.FAILED,
                    lastError = "Пакет ${current.currentBatchIndex} не найден",
                    updatedAt = now(),
                )
                save(current)
                return current
            }

            current = current.copy(
                status = ShareAutomationStatus.OPENING_BATCH,
                updatedAt = now(),
            )
            save(current)

            val openResult = openBatchInYandexMail(current, batch)
            if (!openResult) {
                current = current.copy(
                    status = ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED,
                    lastError = "Не удалось открыть Яндекс Почту для пакета ${batch.index + 1}",
                    updatedAt = now(),
                )
                save(current)
                return current
            }

            current = current.copy(
                status = ShareAutomationStatus.AWAITING_SEND_BUTTON,
                updatedAt = now(),
            )
            save(current)

            val clicked = waitAndClickSendButton()
            if (!clicked) {
                current = current.copy(
                    status = ShareAutomationStatus.PAUSED_MANUAL_ACTION_REQUIRED,
                    lastError = "Кнопка «Отправить» не найдена за 20 секунд",
                    updatedAt = now(),
                )
                save(current)
                return current
            }

            current = current.copy(
                status = ShareAutomationStatus.AUTO_CLICKING_SEND,
                updatedAt = now(),
                lastError = null,
            )
            save(current)

            current = current.copy(
                status = ShareAutomationStatus.AWAITING_MAIL_RESULT,
                updatedAt = now(),
            )
            save(current)

            delay(1200)

            current = current.copy(
                status = ShareAutomationStatus.NEXT_BATCH_TRANSITION,
                currentBatchIndex = current.currentBatchIndex + 1,
                updatedAt = now(),
            )
            save(current)
        }

        current = current.copy(
            status = ShareAutomationStatus.COMPLETED,
            updatedAt = now(),
            lastError = null,
        )
        save(current)
        return current
    }

    fun buildSession(
        recipientEmail: String,
        subjectBase: String,
        targetPackage: String,
        limitBytes: Long,
        photos: List<ShareAutomationPhoto>,
    ): ShareAutomationSession {
        val batches = ShareBatchPlanner.splitByLimit(photos = photos, limitBytes = limitBytes)
        return ShareAutomationSession(
            sessionId = UUID.randomUUID().toString(),
            recipientEmail = recipientEmail.trim(),
            subjectBase = subjectBase.trim().ifBlank { "Фото" },
            targetPackage = targetPackage.ifBlank { "ru.yandex.mail" },
            totalBatches = batches.size,
            currentBatchIndex = 0,
            status = ShareAutomationStatus.IDLE,
            lastError = null,
            updatedAt = now(),
            batches = batches,
        )
    }

    fun resumeSession(): ShareAutomationSession? = progressStore.load()

    fun save(session: ShareAutomationSession) = progressStore.save(session)

    fun clear() = progressStore.clear()

    fun openCurrentBatchManually(): Boolean {
        val session = progressStore.load() ?: return false
        val batch = session.batches.getOrNull(session.currentBatchIndex) ?: return false
        return openBatchInYandexMail(session, batch)
    }

    private fun openBatchInYandexMail(
        session: ShareAutomationSession,
        batch: ShareAutomationBatch,
    ): Boolean {
        return runCatching {
            val uris = ArrayList<Uri>(batch.photos.size)
            batch.photos.forEach { uris.add(Uri.parse(it.uri)) }

            val subject = "${session.subjectBase} (${batch.index + 1}/${session.totalBatches})"
            val body = buildBody(session, batch)

            val sendIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                type = "image/*"
                `package` = session.targetPackage
                putExtra(Intent.EXTRA_EMAIL, arrayOf(session.recipientEmail))
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, body)
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                clipData = buildClipData(uris)
            }
            appContext.startActivity(sendIntent)
            true
        }.getOrElse {
            false
        }
    }

    private fun buildBody(
        session: ShareAutomationSession,
        batch: ShareAutomationBatch,
    ): String {
        val files = batch.photos.joinToString(separator = "\n") { photo ->
            "- ${photo.name}"
        }
        return buildString {
            append("Письмо ${batch.index + 1} из ${session.totalBatches}\n")
            append("Файлов: ${batch.photos.size}\n")
            append("Список файлов:\n")
            append(files)
        }
    }

    private suspend fun waitAndClickSendButton(): Boolean = withContext(Dispatchers.Default) {
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < CLICK_TIMEOUT_MS) {
            if (YandexMailAccessibilityService.tryPerformSendClick()) {
                return@withContext true
            }
            delay(CLICK_RETRY_DELAY_MS)
        }
        false
    }

    private fun buildClipData(uris: List<Uri>): ClipData? {
        if (uris.isEmpty()) {
            return null
        }
        val clipData = ClipData.newRawUri("photos", uris.first())
        for (index in 1 until uris.size) {
            clipData.addItem(ClipData.Item(uris[index]))
        }
        return clipData
    }

    private fun now(): Long = System.currentTimeMillis()

    companion object {
        private const val CLICK_TIMEOUT_MS = 20_000L
        private const val CLICK_RETRY_DELAY_MS = 750L
    }
}

