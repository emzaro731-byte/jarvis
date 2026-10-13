package com.emzaro.jarvis

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MavisScreenReaderService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) { instance = this }
    override fun onInterrupt() {}

    fun scanNow(): String {
        val collected = LinkedHashSet<String>()
        fun walk(node: AccessibilityNodeInfo?) {
            if (node == null || collected.size >= 250) return
            node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { collected.add(it) }
            node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { collected.add(it) }
            for (i in 0 until node.childCount) walk(node.getChild(i))
        }
        try {
            val windows = windows
            for (window in windows) walk(window.root)
            if (collected.isEmpty()) walk(rootInActiveWindow)
        } catch (_: Exception) { walk(rootInActiveWindow) }
        return collected.joinToString("\n").take(12000)
    }

    companion object {
        @Volatile var instance: MavisScreenReaderService? = null
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }
}