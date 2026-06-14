# ── Flutter engine ───────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Flutter references Play Core for deferred components but Kivo does not use
# deferred components. Suppress the missing-class error so R8 succeeds.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── media_kit ────────────────────────────────────────────────────────────────
# media_kit uses JNI reflection to load its native player.
-keep class com.alexmercerind.** { *; }
-keep class dev.alexmercerind.** { *; }
# media_kit_libs_android_video bundles libmpv; keep its JNI entry points.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
# Kotlin coroutines used internally by media_kit.
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ── sqflite ──────────────────────────────────────────────────────────────────
-keep class com.tekartik.sqflite.** { *; }

# ── go_router (dart:mirrors not used, but keep route annotations) ─────────────
-keep @interface ** { *; }

# ── Dart VM / Dart2Java artefacts ────────────────────────────────────────────
-keep class **.R { *; }
-keep class **.R$* { *; }

# ── General Android safety ───────────────────────────────────────────────────
# Prevent stripping of classes loaded via Class.forName().
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-dontwarn java.lang.invoke.**
-dontwarn **$$Lambda$*
