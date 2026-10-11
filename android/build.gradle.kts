// うながすくん Android 版。モジュールは 2 つ:
//   core … 純 Kotlin/JVM。拡張機能 logic.js / iOS の UnagasukunCore と同じ判定ロジック（Android 依存なし）
//   app  … Jetpack Compose の画面と通知
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
