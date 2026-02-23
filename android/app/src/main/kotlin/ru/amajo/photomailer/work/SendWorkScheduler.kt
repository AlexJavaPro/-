package ru.amajo.photomailer.work

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.UUID
import java.util.concurrent.TimeUnit

class SendWorkScheduler(
    private val context: Context,
) {
    fun enqueue(
        jobId: String,
        compressionPreset: String,
    ): UUID {
        val request = OneTimeWorkRequestBuilder<SendMailWorker>()
            .setInputData(
                workDataOf(
                    KEY_JOB_ID to jobId,
                    KEY_COMPRESSION_PRESET to compressionPreset,
                ),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .addTag("photo_mail_send")
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            uniqueWorkName(jobId),
            ExistingWorkPolicy.REPLACE,
            request,
        )
        return request.id
    }

    fun cancel(jobId: String) {
        WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName(jobId))
    }

    companion object {
        const val KEY_JOB_ID = "job_id"
        const val KEY_COMPRESSION_PRESET = "compression_preset"
        const val UNIQUE_WORK_PREFIX = "photo_mail_send_"

        fun uniqueWorkName(jobId: String): String = UNIQUE_WORK_PREFIX + jobId
    }
}
