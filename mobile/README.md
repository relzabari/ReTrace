# ReTrace mobile

Flutter GPS tracking app for exercise recording and replay.

## About

Tap the **ⓘ אודות** icon on the login, setup or active tracking screen. The page displays the installed app's version and build number, read from native package metadata via `package_info_plus` (also available offline). It does not use a separately hardcoded version string.

Toolchain: Flutter >=3.38.1, Dart >=3.10, Java 17. The existing Android project uses AGP 9.0.1, Kotlin 2.3.20 and Gradle 9.1.0. iOS deployment target is 13.0. See `PLATFORM_SETUP.md` for device setup.

## Version and build number

The release version is defined once in `pubspec.yaml`:

```yaml
version: 0.2.1+6
```

`0.2.1` is the visible version; `6` is the build number. Increase the build number for each distributed release. Android requires a higher build number for a normal upgrade (the application ID and signing certificate must also match).

## Android release build

From this directory:

```bash
flutter pub get
flutter build apk --release
```

The standard Flutter APK remains at `build/app/outputs/flutter-apk/app-release.apk`. The existing Gradle copy task additionally creates:

```text
build/app/outputs/flutter-apk/ReTrace-v0.2.1-build6.apk
```

Command-line overrides use the same effective metadata for the installed app and the versioned filename:

```bash
flutter build apk --release --build-name=0.2.2 --build-number=7
```

This produces `ReTrace-v0.2.2-build7.apk`. With `--split-per-abi`, copies retain their architecture suffix (such as `-arm64-v8a.apk`) and use each APK's actual version code. The task reads the current build's artifact metadata, so stale APKs from older builds are not renamed as new releases.

The new naming task no longer creates the ambiguous `ReTrace.apk` alias. Previously generated APKs are not automatically deleted; choose the file matching the version/build being distributed.

## Checks

```bash
flutter analyze
flutter test
```

The About widget tests check actual supplied metadata and error/retry behavior. Verify a release install's About values against the APK filename on a device before distributing it.
