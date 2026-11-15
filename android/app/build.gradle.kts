plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "app.andromac"
    compileSdk = 35
    defaultConfig {
        applicationId = "app.andromac"
        minSdk = 28
        targetSdk = 35
        versionCode = 4
        versionName = "0.4.0"
        ndk { abiFilters += "arm64-v8a" }
    }
    // Private release key lives outside the repo (~/.andromac/signing); builds fall back to unsigned if it is absent.
    val ksDir = File(System.getProperty("user.home"), ".andromac/signing")
    val ksFile = File(ksDir, "android-release.jks")
    val ksPw = File(ksDir, "android-ks.pw").takeIf { it.exists() }?.readText()?.trim()
    signingConfigs {
        if (ksFile.exists() && ksPw != null) create("release") {
            storeFile = ksFile; storePassword = ksPw; keyAlias = "andromac"; keyPassword = ksPw
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false          // kept off on purpose: the embedded Go library uses JNI reflection
            signingConfig = signingConfigs.findByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(files("libs/tunnel.aar"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")   // QR scanner UI from Google Play services, no camera permission needed
}
