import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing credentials from android/key.properties.
// The file is gitignored and must be created manually before a release build.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

android {
    namespace = "com.turtleking.turtle_king"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (keyPropertiesFile.exists()) {
                keyAlias = keyProperties["keyAlias"] as String?
                    ?: error("Release signing requires android/key.properties with keyAlias.")
                keyPassword = keyProperties["keyPassword"] as String?
                    ?: error("Release signing requires android/key.properties with keyPassword.")
                storeFile = file(keyProperties["storeFile"] as? String
                    ?: error("Release signing requires android/key.properties with storeFile."))
                storePassword = keyProperties["storePassword"] as String?
                    ?: error("Release signing requires android/key.properties with storePassword.")
            }
        }
    }

    defaultConfig {
        applicationId = "com.turtleking.turtle_king"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fail the build if key.properties is missing during a release build.
                // The check happens at build time, not configuration time,
                // so debug builds remain unaffected.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
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

// Validate release signing at configuration time if a release task is requested.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("release", ignoreCase = true) } && !keyPropertiesFile.exists()) {
        error("Release signing is not configured. Create android/key.properties with the required signing properties before building a release.")
    }
}
