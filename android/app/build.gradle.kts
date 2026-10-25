plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "jp.nishira.unagasukun"
    compileSdk = 36

    defaultConfig {
        applicationId = "jp.nishira.unagasukun"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "1.0.1"
        // 日本語が既定・英語あり。ほかの言語の androidx リソースは落とす
        resourceConfigurations += listOf("ja", "en")
    }

    // upload key は ~/.gradle/gradle.properties の UNAGASUKUN_UPLOAD_* から読む（鍵もパスワードもリポジトリに置かない）。
    // 無い環境では debug 署名に落ちる（Play には出せない AAB になる）
    val uploadStoreFile = providers.gradleProperty("UNAGASUKUN_UPLOAD_STORE_FILE").orNull
    signingConfigs {
        if (uploadStoreFile != null) {
            create("upload") {
                storeFile = file(uploadStoreFile)
                storePassword = providers.gradleProperty("UNAGASUKUN_UPLOAD_STORE_PASSWORD").get()
                keyAlias = providers.gradleProperty("UNAGASUKUN_UPLOAD_KEY_ALIAS").get()
                keyPassword = providers.gradleProperty("UNAGASUKUN_UPLOAD_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
}
