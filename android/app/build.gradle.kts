import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter plugin is applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter passes --dart-define as Base64 via dart-defines. The same flag is read by app/assembly.dart:
// a fake audio build must not be obtainable with the applicationId of the real build.
val fakeTts = providers.gradleProperty("dart-defines").orNull
    ?.split(',')
    ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    ?.contains("FAKE_TTS=true") == true

android {
    namespace = "io.github.slawa19.audiobook_reader"
    compileSdk = flutter.compileSdkVersion
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.slawa19.audiobook_reader" + if (fakeTts) ".fake" else ""
        manifestPlaceholders["appLabel"] = if (fakeTts) "Book AudioReader (fake)" else "Book AudioReader"
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        // The app version is taken from pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The debug build needs no secrets. Release never falls back to the debug signing.
    signingConfigs {
        create("release") {
            storeFile = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull?.let { file(it) }
            storePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull
            keyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS").orNull
            keyPassword = providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
