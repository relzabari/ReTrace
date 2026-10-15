import com.android.build.api.artifact.SingleArtifact
import com.android.build.api.variant.BuiltArtifactsLoader
import java.io.File
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.exercise_tracker_prototype"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.exercise_tracker_prototype"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

abstract class CopyVersionedApks : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val apkDirectory: DirectoryProperty

    @get:Internal
    abstract val artifactsLoader: Property<BuiltArtifactsLoader>

    @get:OutputDirectory
    abstract val destinationDirectory: DirectoryProperty

    @TaskAction
    fun copyApks() {
        val artifacts = artifactsLoader.get().load(apkDirectory.get())
            ?: error("Cannot read metadata for the release APKs")
        val destination = destinationDirectory.get().asFile
        destination.mkdirs()
        artifacts.elements.forEach { artifact ->
            val version = requireNotNull(artifact.versionName) { "APK has no version name" }
            val build = requireNotNull(artifact.versionCode) { "APK has no version code" }
            fun safeName(value: String) = value.replace(Regex("[^A-Za-z0-9._+-]"), "_")
            val filters = artifact.filters.map { safeName(it.identifier) }.sorted()
            val suffix = if (filters.isEmpty()) "" else "-" + filters.joinToString("-")
            val name = "ReTrace-v${safeName(version)}-build$build$suffix.apk"
            // Read only this build's artifact list: stale APKs from older builds
            // must never be copied and labelled with a new version number.
            File(artifact.outputFile).copyTo(File(destination, name), overwrite = true)
            logger.lifecycle("Versioned APK: ${File(destination, name)}")
        }
    }
}

androidComponents.onVariants(androidComponents.selector().withBuildType("release")) { variant ->
    val variantName = variant.name.replaceFirstChar { it.uppercaseChar() }
    val versionedApks = tasks.register<CopyVersionedApks>("copy${variantName}ApkWithAppName") {
        apkDirectory.set(variant.artifacts.get(SingleArtifact.APK))
        artifactsLoader.set(variant.artifacts.getBuiltArtifactsLoader())
        destinationDirectory.set(layout.buildDirectory.dir("outputs/flutter-apk"))
    }
    tasks.matching { it.name == "assemble$variantName" }.configureEach {
        finalizedBy(versionedApks)
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
