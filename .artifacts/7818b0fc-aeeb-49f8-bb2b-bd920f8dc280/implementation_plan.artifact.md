# Implementation Plan - Fix SecurityException (Unknown calling package name)

This plan aims to resolve the `java.lang.SecurityException: Unknown calling package name 'com.google.android.gms'` error by harmonizing the project's dependency versions and ensuring correct Google Services configuration.

## User Review Required

> [!IMPORTANT]
> This plan involves updating Firebase and Play Services dependency versions. While this is intended to fix compatibility issues, it's recommended to perform a full build and regression test of Firebase features (Auth, Firestore, Messaging) after application.

## Proposed Changes

### Build Configuration

#### [MODIFY] [android/build.gradle.kts](file:///E:/capstone/gdc_sari_sari_admin/android/build.gradle.kts)
- Align the forced Kotlin version in `subprojects` to `1.9.24` to match the project's primary Kotlin version.

#### [MODIFY] [android/settings.gradle.kts](file:///E:/capstone/gdc_sari_sari_admin/android/settings.gradle.kts)
- Update the `com.google.gms.google-services` plugin version to `4.4.2`.

#### [MODIFY] [android/app/build.gradle.kts](file:///E:/capstone/gdc_sari_sari_admin/android/app/build.gradle.kts)
- Update Firebase BoM from `32.8.0` to `33.10.0`.
- Remove the forced `implementation("com.google.android.gms:play-services-base:18.3.0")` to allow the BoM to manage the version.

## Verification Plan

### Manual Verification
1. Run `flutter clean` in the project root.
2. Run `flutter pub get`.
3. Build and run the app: `flutter run`.
4. Verify that the app starts without the `SecurityException` in the logcat.
5. Test a feature that uses Google Play Services (e.g., initializing ML Kit or fetching a Firestore document).
