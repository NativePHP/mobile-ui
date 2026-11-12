package com.nativephp.mobile.ui.nativerender

typealias NativeElementBridge = NativeUIBridge

object NativeUIBridge {
    val events = mutableListOf<String>()
    fun sendTextChangeEvent(callbackId: Int, nodeId: Int, text: String) { events += "change:$callbackId:$text" }
    fun sendSubmitEvent(callbackId: Int, nodeId: Int, text: String) { events += "submit:$callbackId:$text" }
    fun sendPressEvent(callbackId: Int, nodeId: Int) { events += "press:$callbackId" }
    fun sendLongPressEvent(callbackId: Int, nodeId: Int) { events += "longpress:$callbackId" }
    fun sendSliderChangeEvent(callbackId: Int, nodeId: Int, value: Float) { events += "slider:$callbackId:$value" }
    fun sendTabChangeEvent(callbackId: Int, nodeId: Int, index: Int) { events += "tab:$callbackId:$index" }
    fun sendSheetDismissEvent(callbackId: Int, nodeId: Int) { events += "dismiss:$callbackId" }
}
