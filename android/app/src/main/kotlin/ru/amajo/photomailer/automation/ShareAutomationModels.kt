package ru.amajo.photomailer.automation

import org.json.JSONArray
import org.json.JSONObject

data class ShareAutomationPhoto(
    val uri: String,
    val name: String,
    val sizeBytes: Long,
    val mimeType: String?,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("uri", uri)
            .put("name", name)
            .put("sizeBytes", sizeBytes)
            .put("mimeType", mimeType)
    }

    companion object {
        fun fromJson(json: JSONObject): ShareAutomationPhoto {
            return ShareAutomationPhoto(
                uri = json.optString("uri", ""),
                name = json.optString("name", "file"),
                sizeBytes = json.optLong("sizeBytes", 0L),
                mimeType = json.optString("mimeType").ifBlank { null },
            )
        }
    }
}

data class ShareAutomationBatch(
    val index: Int,
    val photos: List<ShareAutomationPhoto>,
    val totalBytes: Long,
) {
    fun toJson(): JSONObject {
        val photosArray = JSONArray()
        photos.forEach { photosArray.put(it.toJson()) }
        return JSONObject()
            .put("index", index)
            .put("totalBytes", totalBytes)
            .put("photos", photosArray)
    }

    companion object {
        fun fromJson(json: JSONObject): ShareAutomationBatch {
            val photosArray = json.optJSONArray("photos") ?: JSONArray()
            val photos = buildList {
                for (i in 0 until photosArray.length()) {
                    val item = photosArray.optJSONObject(i) ?: continue
                    add(ShareAutomationPhoto.fromJson(item))
                }
            }
            return ShareAutomationBatch(
                index = json.optInt("index", 0),
                photos = photos,
                totalBytes = json.optLong("totalBytes", 0L),
            )
        }
    }
}

enum class ShareAutomationStatus(val id: String) {
    IDLE("idle"),
    PRECHECK("precheck"),
    OPENING_BATCH("opening_batch"),
    AWAITING_SEND_BUTTON("awaiting_send_button"),
    AUTO_CLICKING_SEND("auto_clicking_send"),
    AWAITING_MAIL_RESULT("awaiting_mail_result"),
    NEXT_BATCH_TRANSITION("next_batch_transition"),
    COMPLETED("completed"),
    PAUSED_MANUAL_ACTION_REQUIRED("paused_manual_action_required"),
    AUTH_RELOGIN_REQUIRED("auth_relogin_required"),
    FAILED("failed"),
    CANCELLED("cancelled");

    companion object {
        fun fromId(id: String): ShareAutomationStatus {
            return entries.firstOrNull { it.id == id } ?: IDLE
        }
    }
}

data class ShareAutomationSession(
    val sessionId: String,
    val recipientEmail: String,
    val subjectBase: String,
    val targetPackage: String,
    val totalBatches: Int,
    val currentBatchIndex: Int,
    val status: ShareAutomationStatus,
    val lastError: String?,
    val updatedAt: Long,
    val batches: List<ShareAutomationBatch>,
) {
    fun toJson(): JSONObject {
        val batchesArray = JSONArray()
        batches.forEach { batchesArray.put(it.toJson()) }
        return JSONObject()
            .put("sessionId", sessionId)
            .put("recipientEmail", recipientEmail)
            .put("subjectBase", subjectBase)
            .put("targetPackage", targetPackage)
            .put("totalBatches", totalBatches)
            .put("currentBatchIndex", currentBatchIndex)
            .put("status", status.id)
            .put("lastError", lastError)
            .put("updatedAt", updatedAt)
            .put("batches", batchesArray)
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "sessionId" to sessionId,
            "state" to status.id,
            "currentBatchIndex" to currentBatchIndex,
            "totalBatches" to totalBatches,
            "currentBatchNumber" to (currentBatchIndex + 1).coerceAtMost(totalBatches),
            "lastError" to lastError,
            "updatedAt" to updatedAt,
            "recipientEmail" to recipientEmail,
        )
    }

    companion object {
        fun idle(): ShareAutomationSession {
            return ShareAutomationSession(
                sessionId = "",
                recipientEmail = "",
                subjectBase = "",
                targetPackage = "ru.yandex.mail",
                totalBatches = 0,
                currentBatchIndex = 0,
                status = ShareAutomationStatus.IDLE,
                lastError = null,
                updatedAt = System.currentTimeMillis(),
                batches = emptyList(),
            )
        }

        fun fromJson(json: JSONObject): ShareAutomationSession {
            val batchesArray = json.optJSONArray("batches") ?: JSONArray()
            val batches = buildList {
                for (i in 0 until batchesArray.length()) {
                    val item = batchesArray.optJSONObject(i) ?: continue
                    add(ShareAutomationBatch.fromJson(item))
                }
            }
            return ShareAutomationSession(
                sessionId = json.optString("sessionId", ""),
                recipientEmail = json.optString("recipientEmail", ""),
                subjectBase = json.optString("subjectBase", ""),
                targetPackage = json.optString("targetPackage", "ru.yandex.mail"),
                totalBatches = json.optInt("totalBatches", batches.size),
                currentBatchIndex = json.optInt("currentBatchIndex", 0),
                status = ShareAutomationStatus.fromId(json.optString("status", "idle")),
                lastError = json.optString("lastError").ifBlank { null },
                updatedAt = json.optLong("updatedAt", System.currentTimeMillis()),
                batches = batches,
            )
        }
    }
}

