package ru.amajo.photomailer.automation

import android.content.Context
import org.json.JSONObject

class SendProgressStore(
    context: Context,
) {
    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(session: ShareAutomationSession) {
        preferences.edit()
            .putString(KEY_SESSION_JSON, session.toJson().toString())
            .apply()
    }

    fun load(): ShareAutomationSession? {
        val raw = preferences.getString(KEY_SESSION_JSON, null)?.trim().orEmpty()
        if (raw.isBlank()) {
            return null
        }
        return runCatching {
            ShareAutomationSession.fromJson(JSONObject(raw))
        }.getOrNull()
    }

    fun clear() {
        preferences.edit().remove(KEY_SESSION_JSON).apply()
    }

    companion object {
        private const val PREFS_NAME = "share_automation_progress"
        private const val KEY_SESSION_JSON = "automation_session_json"
    }
}

