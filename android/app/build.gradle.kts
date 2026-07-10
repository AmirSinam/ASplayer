import java.util.Properties

plugins {
    id("com.android.application")
    // AGP 8 has no built-in Kotlin, so MainActivity.kt needs the Kotlin plugin
    // applied explicitly. The Flutter plugin must come after both.
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing material comes from one of two places, never from this repository:
//   local builds  -> android/key.properties (git-ignored)
//   CI builds     -> environment variables fed by GitHub secrets
// When neither is present the release build falls back to the debug key, so a
// fresh clone still builds. Such an APK must never be published.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// GitHub Actions hands an unset secret through as an empty string, not as null,
// so blanks have to be folded into null before anything touches the filesystem.
fun signingValue(propertyKey: String, envKey: String): String? =
    (keyProperties.getProperty(propertyKey) ?: System.getenv(envKey))?.takeIf { it.isNotBlank() }

val storeFilePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseKey = storeFilePath != null && file(storeFilePath).exists()

android {
    namespace = "ir.aspoormehr.asplayer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ir.aspoormehr.asplayer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(storeFilePath!!)
                storePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("ASplayer: no release key found, signing with the debug key. Do not publish this build.")
                signingConfigs.getByName("debug")
            }
            // Code shrinking is left off on purpose: R8 strips ExoPlayer classes
            // that just_audio reaches by reflection, and we have no way to test a
            // shrunk build yet. Turn it on once the app runs on a real phone.
        }
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
