plugins {
    id("com.android.library") version "8.13.2"
    id("org.jetbrains.kotlin.android") version "2.3.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.0"
}
val stageSources = tasks.register<Sync>("stageSources") {
    from(layout.projectDirectory.dir("../../resources/android")) {
        include("FilledTextInputRenderer.kt", "OutlinedTextInputRenderer.kt", "TextInputShared.kt", "NativeUIFontResolver.kt", "NativeUITheme.kt", "ButtonRenderer.kt", "GestureAreaRenderer.kt", "ListRenderer.kt", "VirtualListRenderer.kt", "PagerRenderer.kt")
    }
    from(providers.gradleProperty("mobileRoot").map { "$it/resources/androidstudio/app/src/main/java/com/nativephp/mobile/ui/nativerender" }) {
        include("KeyboardFocusPolicy.kt", "NativeUINode.kt", "SharedValueStore.kt")
    }
    into(layout.buildDirectory.dir("generated/upstream"))
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(stageSources) }
android {
    namespace = "com.nativephp.plugins.native_ui.tests"
    compileSdk = 36
    defaultConfig { minSdk = 29 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    testOptions { unitTests.isIncludeAndroidResources = true }
    sourceSets["main"].kotlin.srcDir(stageSources.map { it.destinationDir })
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.12.00"))
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("io.coil-kt.coil3:coil-compose:3.1.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
