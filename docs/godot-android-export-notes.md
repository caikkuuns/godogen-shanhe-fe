# Godot 4.7.2 Android debug export setup (box)

Time: 2026-11-10 Asia/Shanghai. Apt mirrors unreachable; all installs via direct HTTPS.
Repo `/workspace/godogen-shanhe` was **not** modified.

## Status

**Verified:** headless debug APK export works.

```bash
godot --headless --path /tmp/godot-android-test --export-debug "Android" /tmp/godot-android-test/test.apk
# produced 27M APK; unzip shows AndroidManifest.xml, classes.dex, lib/arm64-v8a/libgodot_android.so, resources.arsc, META-INF/*
```

Harmless noise during export (not a failure):
- `Could not find version of build tools that matches Target SDK, using 35.0.1` (docs recommend 35.0.1; export still signed successfully)
- `cannot connect to daemon at tcp:5037` (adb server not running; APK file still produced)
- Scratch project had no icon → warning only

NDK/CMake **not** installed (not required for standard non-Gradle template export).

## Installed paths & versions

| Component | Path / version |
|-----------|----------------|
| Godot | `/usr/local/bin/godot` → `4.7.2.stable.official.ed1daf0bf` |
| Export templates | `~/.local/share/godot/export_templates/4.7.2.stable/` (`version.txt` = `4.7.2.stable`; includes `android_debug.apk` / `android_release.apk` / `android_source.zip`) |
| Temurin JDK 17 | `/home/box/apps/jdk17` → OpenJDK `17.0.21` (Temurin-17.0.21+9) |
| Android SDK root | `/home/box/apps/android-sdk` |
| cmdline-tools | `/home/box/apps/android-sdk/cmdline-tools/latest` (duplicate `latest-2` removed after install) |
| platform-tools | `37.0.1` (`adb` 1.0.41) |
| build-tools | `35.0.1` |
| platforms | `android-35` |
| Debug keystore | `/home/box/.android/debug.keystore` (alias `androiddebugkey`; also copied to `~/.local/share/godot/keystores/debug.keystore`) |

## Editor settings

File: `~/.config/godot/editor_settings-4.7.tres`

```
export/android/java_sdk_path = "/home/box/apps/jdk17"
export/android/android_sdk_path = "/home/box/apps/android-sdk"
export/android/debug_keystore = "/home/box/.android/debug.keystore"
export/android/debug_keystore_pass = "android"
```

## Shell env (`~/.bashrc`)

```bash
export JAVA_HOME=/home/box/apps/jdk17
export ANDROID_HOME=/home/box/apps/android-sdk
export ANDROID_SDK_ROOT=/home/box/apps/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

## Project requirements for Android export

In `project.godot` must enable:

```
[rendering]
textures/vram_compression/import_etc2_astc=true
```

Without that, export fails with: `ETC2/ASTC texture compression is required for Android export`.

## Sample working `export_presets.cfg` (Android, Gradle off)

Working scratch file: `/tmp/godot-android-test/export_presets.cfg`

Essential section (permissions omitted; default all `false` is fine for a minimal test):

```
[preset.0]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="test.apk"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/gradle_build_directory=""
gradle_build/android_source_template=""
gradle_build/compress_native_libraries=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="1.0"
package/unique_name="com.example.godotandroidtest"
package/name="GodotAndroidTest"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_library=true
package/show_as_launcher_app=false
screen/immersive_mode=true
screen/edge_to_edge=false
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
screen/background_color=Color(0, 0, 0, 1)
apk_expansion/enable=false
permissions/custom_permissions=[]
```

Godot fills many `permissions/*=false` keys; a full dump of the verified preset lives at `/tmp/godot-android-test/export_presets.cfg`.

## Verification command & APK contents

```bash
export JAVA_HOME=/home/box/apps/jdk17
export ANDROID_HOME=/home/box/apps/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
godot --headless --path /tmp/godot-android-test --export-debug "Android" /tmp/godot-android-test/test.apk
ls -lh /tmp/godot-android-test/test.apk
unzip -l /tmp/godot-android-test/test.apk | head
```

Key entries observed:

- `classes.dex`
- `lib/arm64-v8a/libgodot_android.so`
- `lib/arm64-v8a/libc++_shared.so`
- `AndroidManifest.xml`
- `resources.arsc`
- `META-INF/*` (signed)

## For Codex / 山河剑行 Godot project

When `/workspace/godogen-shanhe` is ready to export:

1. Ensure `textures/vram_compression/import_etc2_astc=true` in `project.godot`.
2. Add an Android preset with `gradle_build/use_gradle_build=false` (unless Gradle build is intentionally enabled; that would need NDK/CMake).
3. Export with the same env vars / editor settings above.
4. Prefer `arm64-v8a` for modern devices.

## Sources

- Templates: `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
- JDK: Adoptium Temurin 17.0.21+9 Linux x64
- SDK cmdline-tools: `https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip`
- Docs followed: Godot 4.7 “Exporting for Android” (OpenJDK 17, Platform 35, Build-Tools 35.0.1, platform-tools ≥35)
