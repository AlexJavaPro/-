package ru.amajo.photomailer.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

class YandexMailAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        serviceRef = WeakReference(this)
        lastWindowPackage = ""
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString().orEmpty()
        if (pkg.isNotBlank()) {
            lastWindowPackage = pkg
        }
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        serviceRef.clear()
        return super.onUnbind(intent)
    }

    private fun performSendClickInternal(): Boolean {
        val root = rootInActiveWindow ?: return false
        val sendNode = findSendNode(root) ?: return false
        val clicked = clickNode(sendNode)
        if (clicked) {
            lastSendClickAt.set(System.currentTimeMillis())
        }
        return clicked
    }

    private fun findSendNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)

        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            val text = node.text?.toString()?.trim().orEmpty()
            val contentDesc = node.contentDescription?.toString()?.trim().orEmpty()
            val viewId = node.viewIdResourceName?.lowercase(Locale.getDefault()).orEmpty()

            val textMatch = text.equals(BUTTON_TEXT_SEND, ignoreCase = true) ||
                contentDesc.equals(BUTTON_TEXT_SEND, ignoreCase = true)
            val idMatch = viewId.contains("send")
            if ((textMatch || idMatch) && (node.isClickable || node.isEnabled)) {
                return node
            }

            for (index in 0 until node.childCount) {
                node.getChild(index)?.let(queue::add)
            }
        }
        return null
    }

    private fun clickNode(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        repeat(6) {
            if (current == null) {
                return false
            }
            if (current!!.isClickable && current!!.isEnabled) {
                return current!!.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            current = current!!.parent
        }
        return false
    }

    companion object {
        private const val BUTTON_TEXT_SEND = "Отправить"
        private val lastSendClickAt = AtomicLong(0L)

        @Volatile
        private var lastWindowPackage: String = ""

        @Volatile
        private var serviceRef: WeakReference<YandexMailAccessibilityService> = WeakReference(null)

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0,
            ) == 1
            if (!enabled) {
                return false
            }
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ).orEmpty()
            val expected = ComponentName(
                context,
                YandexMailAccessibilityService::class.java,
            ).flattenToString()
            return enabledServices.split(':').any { it.equals(expected, ignoreCase = true) }
        }

        fun openAccessibilitySettings(context: Context) {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }

        fun getState(context: Context): Map<String, Any?> {
            val connected = serviceRef.get() != null
            return mapOf(
                "enabled" to isEnabled(context),
                "connected" to connected,
                "currentPackage" to lastWindowPackage,
                "inYandexMail" to (lastWindowPackage == "ru.yandex.mail"),
                "lastSendClickAt" to lastSendClickAt.get(),
            )
        }

        fun tryPerformSendClick(): Boolean {
            val service = serviceRef.get() ?: return false
            return service.performSendClickInternal()
        }
    }
}

