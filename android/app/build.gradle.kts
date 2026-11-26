import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load production release keystore credentials from `android/key.properties` or CI environment variables.
// See `android/key.properties.example` and `docs/release/SIGNING_MIGRATION.md` for production signing setup.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val propStoreFile = keystoreProperties.getProperty("storeFile")?.trim()?.takeIf { it.isNotEmpty() }
val envStoreFile = System.getenv("LIFEOS_RELEASE_STORE_FILE")?.trim()?.takeIf { it.isNotEmpty() }
val resolvedStoreFile = when {
    propStoreFile != null -> rootProject.file(propStoreFile)
    envStoreFile != null -> file(envStoreFile)
    else -> null
}?.takeIf { it.exists() && it.isFile }
val resolvedStorePassword = (
    keystoreProperties.getProperty("storePassword")
        ?: System.getenv("LIFEOS_RELEASE_STORE_PASSWORD")
    )?.trim()
val resolvedKeyAlias = (
    keystoreProperties.getProperty("keyAlias")
        ?: System.getenv("LIFEOS_RELEASE_KEY_ALIAS")
    )?.trim()
val resolvedKeyPassword = (
    keystoreProperties.getProperty("keyPassword")
        ?: System.getenv("LIFEOS_RELEASE_KEY_PASSWORD")
    )?.trim()

val hasReleaseKeystore = resolvedStoreFile != null &&
    !resolvedStorePassword.isNullOrBlank() &&
    resolvedStorePassword != "CHANGE_ME_STORE_PASSWORD" &&
    !resolvedKeyAlias.isNullOrBlank() &&
    !resolvedKeyPassword.isNullOrBlank() &&
    resolvedKeyPassword != "CHANGE_ME_KEY_PASSWORD"

val requireReleaseKeystore =
    System.getenv("LIFEOS_REQUIRE_RELEASE_SIGNING")?.equals("true", ignoreCase = true) == true ||
        System.getenv("GITHUB_REF")?.startsWith("refs/tags/v") == true ||
        System.getenv("CI")?.equals("true", ignoreCase = true) == true

val allowDebugSignedRelease =
    !requireReleaseKeystore &&
        System.getenv("LIFEOS_ALLOW_DEBUG_SIGNED_RELEASE")?.equals("true", ignoreCase = true) == true

android {
    namespace = "vn.lifeos.app.life_os"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "vn.lifeos.app.life_os"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        buildConfig = true
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("github") {
            dimension = "distribution"
            buildConfigField("boolean", "ENABLE_GITHUB_OTA", "true")
            buildConfigField("String", "DISTRIBUTION_FLAVOR", "\"github\"")
        }
        create("play") {
            dimension = "distribution"
            buildConfigField("boolean", "ENABLE_GITHUB_OTA", "false")
            buildConfigField("String", "DISTRIBUTION_FLAVOR", "\"play\"")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = resolvedStoreFile
                storePassword = resolvedStorePassword
                keyAlias = resolvedKeyAlias
                keyPassword = resolvedKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugSignedRelease) {
                logger.warn(
                    "LifeOS Signing Warning: Signing non-distributable local release build with Android Debug key " +
                        "(LIFEOS_ALLOW_DEBUG_SIGNED_RELEASE=true). Applying versionNameSuffix=-debugsigned."
                )
                versionNameSuffix = "-debugsigned"
                signingConfig = signingConfigs.getByName("debug")
            } else {
                // Fail-closed: never fall back to debug signing silently.
                signingConfig = null
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

gradle.taskGraph.whenReady {
    if (!hasReleaseKeystore && !allowDebugSignedRelease) {
        val requestedReleaseTasks = allTasks.filter { task ->
            task.project == project && task.name.contains("Release")
        }
        if (requestedReleaseTasks.isNotEmpty()) {
            throw org.gradle.api.GradleException(
                "F16 / APP-02 Security Gate (FAIL-CLOSED): Release build (${requestedReleaseTasks.first().name}) " +
                    "requires a valid production release keystore via android/key.properties or " +
                    "LIFEOS_RELEASE_STORE_FILE / LIFEOS_RELEASE_STORE_PASSWORD / LIFEOS_RELEASE_KEY_ALIAS / LIFEOS_RELEASE_KEY_PASSWORD. " +
                    "Refusing to fall back to Android Debug signing key. " +
                    "For local non-distributable testing only, opt in explicitly with LIFEOS_ALLOW_DEBUG_SIGNED_RELEASE=true."
            )
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}
