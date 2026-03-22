import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties for release signing
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
var keystoreConfigured = false

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))

    val requiredKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    val missingKeys = requiredKeys.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }

    if (missingKeys.isEmpty()) {
        var storeFilePath = keystoreProperties.getProperty("storeFile")
        if (storeFilePath.startsWith("~")) {
            storeFilePath = storeFilePath.replaceFirst("~", System.getProperty("user.home"))
        }
        val storeFile = file(storeFilePath)
        if (storeFile.exists()) {
            keystoreConfigured = true
            println("✅ Release signing configuration ready: ${storeFile.absolutePath}")
        } else {
            println("❌ Keystore not found at: ${storeFile.absolutePath}")
        }
    } else {
        println("❌ key.properties missing: ${missingKeys.joinToString(", ")}")
    }
} else {
    println("⚠️  key.properties not found — debug builds will use default debug keystore")
}

android {
    namespace = "com.tinkerplexlabs.issueinator"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tinkerplexlabs.issueinator"
        minSdk = 34
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreConfigured) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Use release signing for debug builds too (for Google Sign-In SHA-1 match)
            signingConfig = if (keystoreConfigured) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }

        getByName("release") {
            if (keystoreConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
