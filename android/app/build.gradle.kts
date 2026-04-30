import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun requiredKeystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)
        ?: throw org.gradle.api.GradleException("Missing '$name' in ${keystorePropertiesFile.path}")

android {
    namespace = "com.flutter.duu233"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.flutter.duu233"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val releaseStoreFile = file(requiredKeystoreProperty("storeFile"))
            if (!releaseStoreFile.exists()) {
                throw org.gradle.api.GradleException("Keystore file not found: ${releaseStoreFile.path}")
            }

            keyAlias = requiredKeystoreProperty("keyAlias")
            keyPassword = requiredKeystoreProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = requiredKeystoreProperty("storePassword")
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
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
