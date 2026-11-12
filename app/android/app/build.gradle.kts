import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Two builds come out of this one project:
//  - the default (sideload) build: `com.gazsesz.dmx_controller`, signed with the
//    committed debug key, exactly as before. This is the APK that goes on the tablet.
//  - the Google Play build: `smart.dmx.app`, signed with the private upload key.
//    Switched on with DMX_PLAY_BUILD=true (CI: "Build Play bundle" workflow).
// Different application ids, so both can live side by side on one device.
val playBuild = System.getenv("DMX_PLAY_BUILD") == "true"

// Upload-key settings: environment variables (CI) win, then android/key.properties
// (local builds; git-ignored). Never commit the key or its passwords.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun uploadSetting(env: String, prop: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProperties.getProperty(prop)

android {
    namespace = "com.gazsesz.dmx_controller"
    // flutter.compileSdkVersion lagged behind what flutter_plugin_android_lifecycle
    // requires (36+); pin explicitly instead of relying on the Flutter template default.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The Play id is permanent once uploaded; never change it.
        applicationId = if (playBuild) "smart.dmx.app" else "com.gazsesz.dmx_controller"
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

    signingConfigs {
        getByName("debug") {
            // A fixed, repo-committed debug key (not the per-machine
            // ~/.android/debug.keystore) so every build — local or CI —
            // signs identically. Otherwise each fresh CI runner mints its
            // own random debug key and `adb install` refuses to upgrade an
            // existing install ("signatures do not match").
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (playBuild) {
            create("upload") {
                val storePath = uploadSetting("DMX_UPLOAD_STORE_FILE", "storeFile")
                    ?: throw GradleException(
                        "Play build needs the upload key: set DMX_UPLOAD_STORE_FILE, " +
                            "DMX_UPLOAD_STORE_PASSWORD, DMX_UPLOAD_KEY_ALIAS, " +
                            "DMX_UPLOAD_KEY_PASSWORD (or android/key.properties).",
                    )
                storeFile = file(storePath)
                storePassword = uploadSetting("DMX_UPLOAD_STORE_PASSWORD", "storePassword")
                keyAlias = uploadSetting("DMX_UPLOAD_KEY_ALIAS", "keyAlias")
                keyPassword = uploadSetting("DMX_UPLOAD_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sideload builds keep the committed debug key so `adb install`
            // upgrades the tablet in place; the Play build uses the upload key.
            signingConfig = signingConfigs.getByName(if (playBuild) "upload" else "debug")
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
