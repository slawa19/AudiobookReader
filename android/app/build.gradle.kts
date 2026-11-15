plugins {
    id("com.android.application")
    // Flutter подключается после плагина Android.
    id("dev.flutter.flutter-gradle-plugin")
}

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
        applicationId = "io.github.slawa19.audiobook_reader"
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        // Версия приложения берётся из pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Отладочная сборка не требует секретов. У release никогда нет подмены на debug.
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
