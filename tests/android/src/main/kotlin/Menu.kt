package com.nativephp.plugins.native_ui.ui

import androidx.compose.runtime.Composable
import com.nativephp.mobile.ui.nativerender.NativeUINode

@Composable
fun ExpressiveMenu(expanded: Boolean, onDismissRequest: () -> Unit, content: @Composable () -> Unit) {}
@Composable
fun renderAttachedMenuItem(item: NativeUINode, onDismiss: () -> Unit) {}
