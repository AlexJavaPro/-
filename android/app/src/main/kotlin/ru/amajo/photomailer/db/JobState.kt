package ru.amajo.photomailer.db

object JobState {
    const val QUEUED = "queued"
    const val RUNNING = "running"
    const val RETRYING = "retrying"
    const val SUCCEEDED = "succeeded"
    const val FAILED = "failed"
    const val CANCELLED = "cancelled"
}

