import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties, which is NOT in version
// control — it holds the keystore password. See RELEASING.md to create one.
// Without it, a release build still succeeds but is signed with the debug key
// and cannot be uploaded to Play; the build warns loudly rather than producing
// an unusable artifact silently.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.retrobeat.retrobeat"
    compileSdk = flutter.compileSdkVersion
    // Pinned to the installed NDK so release symbol stripping works; the
    // Flutter-computed default doesn't match what's on this machine.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.retrobeat.retrobeat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falling back to the debug key keeps `flutter build apk --release`
            // working for sideloading, which is what it is mostly used for.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// An App Bundle exists for exactly one purpose: uploading to Google Play. A
// debug-signed one is rejected there, so producing it silently just wastes the
// upload. Gradle's own warnings are swallowed by the Flutter CLI, so this fails
// the build outright rather than handing over an artifact that looks fine.
if (!hasReleaseKeystore) {
    tasks.matching { it.name == "bundleRelease" }.configureEach {
        doFirst {
            throw GradleException(
                "\n\n" +
                    "Cannot build a release App Bundle: android/key.properties is missing.\n\n" +
                    "  An .aab is only ever uploaded to Google Play, and Play rejects\n" +
                    "  anything signed with the debug key — which is what this would be.\n\n" +
                    "  Create a keystore and key.properties first: see RELEASING.md.\n\n" +
                    "  (If you only want something to sideload, use:\n" +
                    "     flutter build apk --release\n" +
                    "   which is debug-signed on purpose and installs fine.)\n",
            )
        }
    }
}

flutter {
    source = "../.."
}
