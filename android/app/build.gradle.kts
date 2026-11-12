import java.io.FileInputStream
import java.util.Properties

val keyPropertiesFile = sequenceOf(
    rootProject.file("key.properties"),
    rootProject.file("../key.properties"),
).firstOrNull { it.isFile }
val keyProperties = Properties()
keyPropertiesFile?.let { FileInputStream(it).use(keyProperties::load) }

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "id.ac.unugha.labflow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "id.ac.unugha.labflow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += listOf("environment")

    productFlavors {
        create("production") {
            dimension = "environment"
        }
        create("localUat") {
            dimension = "environment"
        }
    }

    signingConfigs {
        create("release") {
            if (keyPropertiesFile == null) {
                throw GradleException(
                    "Release signing is not configured: key.properties was not found. " +
                        "Create android/key.properties with storeFile, storePassword, " +
                        "keyAlias, and keyPassword."
                )
            }

            val storeFilePath = keyProperties.getProperty("storeFile")?.trim()
            val storePasswordValue = keyProperties.getProperty("storePassword")?.trim()
            val keyAliasValue = keyProperties.getProperty("keyAlias")?.trim()
            val keyPasswordValue = keyProperties.getProperty("keyPassword")?.trim()
            if (listOf(storeFilePath, storePasswordValue, keyAliasValue, keyPasswordValue)
                    .any { it.isNullOrEmpty() }) {
                throw GradleException(
                    "Release signing is not configured: key.properties must define " +
                        "storeFile, storePassword, keyAlias, and keyPassword."
                )
            }

            val signingFile = file(storeFilePath!!)
            if (!signingFile.isFile) {
                throw GradleException(
                    "Release signing keystore was not found at the configured storeFile path."
                )
            }

            storeFile = signingFile
            storePassword = storePasswordValue
            keyAlias = keyAliasValue
            keyPassword = keyPasswordValue
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
