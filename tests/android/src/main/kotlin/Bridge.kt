package com.nativephp.mobile.ui.nativerender

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color

typealias NativeElementBridge = NativeUIBridge
val LocalAvailableHeight = compositionLocalOf { 800f }

object NativeUIBridge {
    val events = mutableListOf<String>()
    fun sendTextChangeEvent(callbackId: Int, nodeId: Int, text: String) { events += "change:$callbackId:$text" }
    fun sendSubmitEvent(callbackId: Int, nodeId: Int, text: String) { events += "submit:$callbackId:$text" }
    fun sendPressEvent(callbackId: Int, nodeId: Int) { events += "press:$callbackId" }
    fun sendSliderChangeEvent(callbackId: Int, nodeId: Int, value: Float) { events += "slider:$callbackId:$value" }
    fun sendTabChangeEvent(callbackId: Int, nodeId: Int, index: Int) { events += "tab:$callbackId:$index" }
}
fun argbToComposeColor(argb: Int) = Color(argb)
