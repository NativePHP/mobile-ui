package com.nativephp.plugins.native_ui.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.nativephp.mobile.ui.nativerender.DefaultContainerNode
import com.nativephp.mobile.ui.nativerender.NativeUINode

/**
 * Sign in with Apple has no Android button, so this draws nothing unless the
 * tag has children, which render as an Android-only fallback (laid out like a
 * column). The iOS renderer draws Apple's button and ignores the children.
 */
object SignInWithAppleButtonRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        if (node.children.isNotEmpty()) {
            DefaultContainerNode(node, modifier)
        }
    }
}
