import java.net.URI
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key, kept out of the repo (key.properties is gitignored).
// Every kuhy release APK is signed with the one shared key, so updates install
// over each other instead of forcing an uninstall (which wipes app data).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// The English model (tessdata_fast, Apache-2.0, ~4 MB). Too big for git
// (pre-commit caps files at 2000 KB), so it is fetched at build time from a
// pinned upstream commit, checked against a pinned sha256 and cached in the
// Gradle user home; a wrong hash fails the build.
val tessdataSha256 = "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"
val tessdataUrl =
    "https://github.com/tesseract-ocr/tessdata_fast/raw/" +
        "87416418657359cb625c412a48b6e1d6d41c29bd/eng.traineddata"
val tessdataDir = layout.buildDirectory.dir("generated/tessdata")

fun sha256(file: File): String =
    MessageDigest.getInstance("SHA-256").digest(file.readBytes())
        .joinToString("") { "%02x".format(it) }

val fetchTessdata = tasks.register("fetchTessdata") {
    val cached = File(gradle.gradleUserHomeDir, "book-guard/eng-$tessdataSha256.traineddata")
    val target = tessdataDir.map { it.file("tessdata/eng.traineddata").asFile }
    outputs.file(target)
    doLast {
        if (!cached.exists() || sha256(cached) != tessdataSha256) {
            cached.parentFile.mkdirs()
            val part = File(cached.path + ".part")
            URI(tessdataUrl).toURL().openStream().use { input ->
                part.outputStream().use { input.copyTo(it) }
            }
            check(sha256(part) == tessdataSha256) { "eng.traineddata sha256 mismatch" }
            part.renameTo(cached)
        }
        target.get().parentFile.mkdirs()
        cached.copyTo(target.get(), overwrite = true)
    }
}

android {
    namespace = "com.kuhy.book_guard_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets.getByName("main").assets.srcDir(tessdataDir.get().asFile)

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kuhy.book_guard_app"
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
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            // Debug key only when key.properties is absent (a fresh clone).
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Every task that packs or reads the assets waits for the model.
tasks.matching { it.name.endsWith("Assets") }.configureEach {
    dependsOn(fetchTessdata)
}

dependencies {
    implementation(libs.tesseract4android)
}

flutter {
    source = "../.."
}
