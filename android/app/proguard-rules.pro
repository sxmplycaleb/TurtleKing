# Flutter-specific ProGuard rules for release builds.

# Keep Flutter engine and Dart runtime.
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep Bluetooth Low Energy plugin.
-keep class com.bacnetz.bluetooth_low_energy.** { *; }

# Keep ML Kit / Google Play Services for QR scanning.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep Play Core SplitCompat (referenced by Flutter embedding, not bundled).
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep the MainActivity method channel.
-keep class com.turtleking.turtle_king.MainActivity { *; }

# Kotlin metadata.
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# Enum support.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
