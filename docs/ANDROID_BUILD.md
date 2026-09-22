# Android build environment

Use `tool/build_android.ps1` on Windows with JDK 17 or 21. The project uses Gradle 8.12, which supports JDK 21 but not JDK 25. Do not upgrade Gradle or change the acoustic codec just to match the globally selected Android Studio runtime.

```powershell
flutter pub get
.\tool\build_android.ps1 -JdkPath 'C:\path\to\jdk-21'
```

The script also finds this workspace's verified JDK under the parent `.tooling` directory. It sets Java only for the current build process and restores the previous environment afterward. It does not change Flutter's global Java selection.

## Windows local-socket failure

The original failure happened before compilation: `Unable to establish loopback connection`, caused by `UnixDomainSockets.connect0` reporting `Invalid argument: connect` while creating a Java NIO selector.

JDK 21 alone did not solve it. Setting `jdk.net.unixdomain.tmpdir` to a dedicated short directory outside the redirected Windows TEMP location allowed Gradle's daemon connection to start. The script creates `%USERPROFILE%\.codex\acoustic-beacon-tmp` and passes that property through `JAVA_TOOL_OPTIONS` so child Java processes inherit it. No firewall rules or system network settings are changed.

The behavior and property were checked against `UnixDomainSocketsUtil.java` in the installed JDK's `lib/src.zip`. The JDK looks for the system property before falling back to TEMP.

## JDK provenance

Temurin 21.0.12.1+1, Windows x64, from the official Adoptium API and release:
https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip

Archive SHA256, verified before extraction:
`f9d6e191ab098c0d416e7d588a24420a8621cd2f4720dab2459b8b7b2d2d8b4e`

Compatibility reference: https://docs.gradle.org/current/userguide/compatibility.html

## APK installation

The build script produces `build/app/outputs/flutter-apk/app-debug.apk`. This is a development-signed, debuggable APK, suitable for physical testing rather than distribution.

Copy the APK to the Android phone, open it, and allow installation from that file-transfer/browser app if prompted. Alternatively, with USB debugging authorized:

```powershell
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Open Acoustic Beacon, allow microphone permission, and keep it foregrounded. Follow the audible 4/5 kHz control followed by the 20/21 kHz trial in README. Physical microphone acceptance remains a separate test from APK compilation.

## Rebuild and ABI safeguards

The script runs `flutter clean` followed by `flutter pub get --enforce-lockfile` before compiling. This avoids a Flutter 3.32 incremental dependency-file issue that interpreted the Windows path `Kevin Brown` as `Kevin\ Brown`. Cleaning removes generated build outputs, not application source. Locked dependencies remain unchanged.

Android packaging is restricted to `armeabi-v7a`, `arm64-v8a`, and `x86_64`. A transitive native library originally also contributed an `x86` directory without a matching Flutter engine; that incomplete architecture is now excluded. No Dart application, DSP, protocol, test, or WAV generation code was changed.

The first successful build reported nonfatal third-party Kotlin-metadata/D8 and deprecated Java/Gradle warnings. These do not substitute for a physical launch and microphone test; native runtime behavior remains to be verified on the phone. Build-tool/package upgrades were not used to change application behavior.
