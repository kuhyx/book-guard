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

// The English models, fetched at build time (too big for git: pre-commit caps
// files at 2000 KB) from pinned upstream commits, checked against pinned
// sha256s and cached in the Gradle user home; a wrong hash fails the build.
//  * fast: tessdata_fast (Apache-2.0, ~4 MB), reads every page.
//  * full: tessdata (Apache-2.0, ~23 MB), the second opinion when fast has
//    nothing usable (it reads the bold p. 611 the fast one misreads).
val tessdataDir = layout.buildDirectory.dir("generated/tessdata")

fun sha256(file: File): String =
    MessageDigest.getInstance("SHA-256").digest(file.readBytes())
        .joinToString("") { "%02x".format(it) }

fun fetchModel(task: String, sha: String, url: String, folder: String) =
    tasks.register(task) {
        val cached = File(gradle.gradleUserHomeDir, "book-guard/eng-$sha.traineddata")
        val target = tessdataDir.map { it.file("$folder/eng.traineddata").asFile }
        outputs.file(target)
        doLast {
            if (!cached.exists() || sha256(cached) != sha) {
                cached.parentFile.mkdirs()
                val part = File(cached.path + ".part")
                URI(url).toURL().openStream().use { input ->
                    part.outputStream().use { input.copyTo(it) }
                }
                check(sha256(part) == sha) { "eng.traineddata sha256 mismatch" }
                part.renameTo(cached)
            }
            target.get().parentFile.mkdirs()
            cached.copyTo(target.get(), overwrite = true)
        }
    }

val fetchTessdata = fetchModel(
    "fetchTessdata",
    "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
    "https://github.com/tesseract-ocr/tessdata_fast/raw/" +
        "87416418657359cb625c412a48b6e1d6d41c29bd/eng.traineddata",
    "tessdata",
)
val fetchTessdataFull = fetchModel(
    "fetchTessdataFull",
    "daa0c97d651c19fba3b25e81317cd697e9908c8208090c94c3905381c23fc047",
    "https://github.com/tesseract-ocr/tessdata/raw/" +
        "ced78752cc61322fb554c280d13360b35b8684e4/eng.traineddata",
    "tessdata_full",
)

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
    dependsOn(fetchTessdata, fetchTessdataFull)
}

dependencies {
    implementation(libs.tesseract4android)
}

flutter {
    source = "../.."
}
