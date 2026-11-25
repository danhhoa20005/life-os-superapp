import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load production release keystore credentials from `android/key.properties` or CI environment variables.
// See `android/key.properties.example` for Play App Signing / production key setup.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val envStoreFile = System.getenv("LIFEOS_RELEASE_STORE_FILE")
val hasReleaseKeystore = (keystoreProperties.getProperty("storeFile")?.isNotBlank() == true &&
    rootProject.file(keystoreProperties.getProperty("storeFile")).exists()) ||
    (!envStoreFile.isNullOrBlank() && file(envStoreFile).exists())

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
                val storePath = keystoreProperties.getProperty("storeFile") ?: envStoreFile!!
                storeFile = if (keystorePropertiesFile.exists()) rootProject.file(storePath) else file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: System.getenv("LIFEOS_RELEASE_STORE_PASSWORD")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: System.getenv("LIFEOS_RELEASE_KEY_ALIAS")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: System.getenv("LIFEOS_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val requireReleaseKeystore =
                System.getenv("LIFEOS_REQUIRE_RELEASE_SIGNING")?.equals("true", ignoreCase = true) == true ||
                    System.getenv("GITHUB_REF")?.startsWith("refs/tags/v") == true
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (requireReleaseKeystore) {
                throw org.gradle.api.GradleException(
                    "F16 / APP-02 Security Gate: Tagged or CI production release build requires a valid release keystore " +
                        "(android/key.properties or LIFEOS_RELEASE_STORE_FILE). Refusing to fall back to debug signing key."
                )
            } else {
                logger.lifecycle(
                    "LifeOS Signing Notice: android/key.properties not found; falling back to local dev keystore for non-tagged local build only."
                )
                signingConfig = signingConfigs.getByName("debug")
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
