package ru.amajo.photomailer.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface JobDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(job: JobEntity)

    @Query("SELECT * FROM send_jobs WHERE jobId = :jobId LIMIT 1")
    suspend fun findById(jobId: String): JobEntity?

    @Query(
        "SELECT * FROM send_jobs " +
            "WHERE state IN ('queued', 'running', 'retrying') " +
            "ORDER BY updatedAt DESC LIMIT 1",
    )
    suspend fun findLatestActive(): JobEntity?

    @Query("SELECT * FROM send_jobs ORDER BY updatedAt DESC LIMIT 1")
    suspend fun findLatest(): JobEntity?

    @Query(
        "UPDATE send_jobs " +
            "SET state = :state, updatedAt = :updatedAt, lastError = :lastError " +
            "WHERE jobId = :jobId",
    )
    suspend fun updateState(
        jobId: String,
        state: String,
        updatedAt: Long,
        lastError: String?,
    )

    @Query(
        "UPDATE send_jobs " +
            "SET totalBatches = :totalBatches, sentBatches = :sentBatches, updatedAt = :updatedAt " +
            "WHERE jobId = :jobId",
    )
    suspend fun updateProgress(
        jobId: String,
        totalBatches: Int,
        sentBatches: Int,
        updatedAt: Long,
    )

    @Query(
        "UPDATE send_jobs " +
            "SET sentBatches = :sentBatches, updatedAt = :updatedAt " +
            "WHERE jobId = :jobId",
    )
    suspend fun updateSentBatches(
        jobId: String,
        sentBatches: Int,
        updatedAt: Long,
    )

    @Query("DELETE FROM send_jobs WHERE jobId = :jobId")
    suspend fun deleteById(jobId: String)
}
