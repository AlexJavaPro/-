package ru.amajo.photomailer.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface LogDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(log: LogEntity): Long

    @Query(
        "SELECT * FROM send_logs " +
            "WHERE jobId = :jobId AND (:afterId IS NULL OR id > :afterId) " +
            "ORDER BY id ASC LIMIT :limit",
    )
    suspend fun listByJob(
        jobId: String,
        afterId: Long?,
        limit: Int = 200,
    ): List<LogEntity>
}

