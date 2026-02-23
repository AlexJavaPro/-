package ru.amajo.photomailer.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "send_jobs")
data class JobEntity(
    @PrimaryKey val jobId: String,
    val senderEmail: String,
    val recipientEmail: String,
    val subjectInput: String,
    val limitBytes: Long,
    val state: String,
    val totalBatches: Int,
    val sentBatches: Int,
    val lastError: String?,
    val createdAt: Long,
    val updatedAt: Long,
)

