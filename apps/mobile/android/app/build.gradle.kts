import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored) or ESPFACE_KEYSTORE* env vars; unsigned release without either.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    (keyProps.getProperty(prop) ?: System.getenv(env))?.takeIf { it.isNotBlank() }
val releaseStoreFile = signingValue("storeFile", "ESPFACE_KEYSTORE")
val hasReleaseKey = releaseStoreFile != null

// versionCode = pubspec build number * 10, +1/+2/+3 per ABI split (RELEASE.md); never contains a 4.
val baseVersionCode = flutter.versionCode * 10
val abiDigit = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)

android {
    namespace = "dev.manzari.espface"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Lowercase id required by Gradle; the display name stays "espFace" (strings.xml / ESPFACE_APP_NAME).
        applicationId = "dev.manzari.espface"
        // flutter_secure_storage and camera need API 23+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = baseVersionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "ESPFACE_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ESPFACE_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ESPFACE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // F-Droid / reproducible builds: no encrypted dependency-info blob in APK or AAB.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

if (!hasReleaseKey && gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    logger.warn("WARNING: no release key (android/key.properties or ESPFACE_KEYSTORE): release output is UNSIGNED. See RELEASE.md.")
}

// Registered after the Flutter plugin's configureEach, so it replaces Flutter's abi*1000+code split codes (x86_64 = 4xxx).
@Suppress("DEPRECATION")
android.applicationVariants.configureEach {
    outputs.forEach { output ->
        @Suppress("DEPRECATION")
        val abi = (output as com.android.build.gradle.api.ApkVariantOutput)
            .getFilter(com.android.build.VariantOutput.FilterType.ABI)
        output.versionCodeOverride = baseVersionCode + (abiDigit[abi] ?: 0)
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
