package com.nativephp.mobile.ui.nativerender

import androidx.compose.ui.graphics.Color

object NativeUIBridge {
    val events = mutableListOf<String>()
    fun sendTextChangeEvent(callbackId: Int, nodeId: Int, text: String) { events += "change:$callbackId:$text" }
    fun sendSubmitEvent(callbackId: Int, nodeId: Int, text: String) { events += "submit:$callbackId:$text" }
    fun sendPressEvent(callbackId: Int, nodeId: Int) { events += "press:$callbackId" }
}
fun argbToComposeColor(argb: Int) = Color(argb)
