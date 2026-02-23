package ru.amajo.photomailer.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface PhotoDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(photos: List<PhotoEntity>)

    @Query("SELECT * FROM job_photos WHERE jobId = :jobId ORDER BY id ASC")
    suspend fun listByJob(jobId: String): List<PhotoEntity>
}

