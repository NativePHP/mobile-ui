package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.DismissibleDrawerSheet
import androidx.compose.material3.DismissibleNavigationDrawer
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.RenderNode
import kotlinx.coroutines.launch

/**
 * Hosts the content-agnostic layout drawer (`native_drawer`) using the
 * idiomatic Material primitive for each mode:
 *   - `modal`  → [ModalNavigationDrawer] (slides over content with a scrim).
 *   - `reveal` → [DismissibleNavigationDrawer] (pushes content aside).
 *
 * Registered on core's `NativeRootHostRegistry` from this plugin's init
 * function ([registerNativeUIChrome]); core folds it around the rendered tree.
 * The drawer content is arbitrary — its children render through the generic
 * [RenderNode]. Self-contained: it draws its own ☰ affordance and owns its
 * `DrawerState`, so it needs no shared state from core. When `drawerNode` is
 * null this is a transparent pass-through.
 */
@Composable
fun NativeLayoutDrawerHost(
    drawerNode: NativeUINode?,
    content: @Composable () -> Unit,
) {
    if (drawerNode == null) {
        content()
        return
    }

    val mode = drawerNode.props.getString("mode", "modal")
    val widthDp = drawerNode.props.getInt("width", 0)
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    val sheetModifier = if (widthDp > 0) Modifier.width(widthDp.dp) else Modifier

    // The ☰ affordance is drawn here (top-start overlay) rather than in a
    // top-bar renderer, so the button is guaranteed present regardless of
    // which chrome (or none) the screen uses.
    val wrappedContent: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize()) {
            content()
            if (drawerState.isClosed) {
                IconButton(
                    onClick = { scope.launch { drawerState.open() } },
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .statusBarsPadding()
                        .padding(start = 4.dp, top = 8.dp)
                ) {
                    Icon(Icons.Filled.Menu, contentDescription = "Open menu")
                }
            }
        }
    }

    if (mode == "reveal") {
        DismissibleNavigationDrawer(
            drawerState = drawerState,
            drawerContent = {
                DismissibleDrawerSheet(modifier = sheetModifier) {
                    DrawerChildren(drawerNode)
                }
            },
            content = wrappedContent
        )
    } else {
        ModalNavigationDrawer(
            drawerState = drawerState,
            drawerContent = {
                ModalDrawerSheet(modifier = sheetModifier) {
                    DrawerChildren(drawerNode)
                }
            },
            content = wrappedContent
        )
    }
}

@Composable
private fun DrawerChildren(drawerNode: NativeUINode) {
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .verticalScroll(rememberScrollState())
    ) {
        drawerNode.children.forEach { child ->
            RenderNode(child)
        }
    }
}
