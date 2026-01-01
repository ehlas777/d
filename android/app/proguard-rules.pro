# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Pigeon (generated code for platform channels)
-keep class **.pigeon.** { *; }
-keepclassmembers class **.pigeon.** { *; }

# Play Core (for split APKs)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep data classes for API models
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Gson specific classes
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep all model classes (adjust package name if needed)
-keep class com.example.qaznat_vt.models.** { *; }

# Dio HTTP client
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# FFmpeg kit (ffmpeg_kit_flutter_new)
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**
-keepclasseswithmembernames class * {
    native <methods>;
}

# (Legacy/other forks)
-keep class com.arthenica.** { *; }

# Whisper
-keep class com.whispercppdemo.** { *; }

# Video player
-keep class io.flutter.plugins.videoplayer.** { *; }

# File picker - CRITICAL for video selection
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class ** implements com.mr.flutter.plugin.filepicker.FilePickerPlugin { *; }

# Shared Preferences - CRITICAL for login
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class ** implements io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin { *; }

# Secure storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Gal (gallery saver)
-keep class ch.nico.gal.** { *; }

# Package info - CRITICAL for version display
-keep class io.flutter.plugins.packageinfo.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class ** implements io.flutter.plugins.packageinfo.PackageInfoPlugin { *; }
-keepclassmembers class ** {
    @io.flutter.plugin.common.MethodChannel.MethodCallHandler *;
}
# Keep all methods and fields for PackageInfo data class
-keepclassmembers class dev.fluttercommunity.plus.packageinfo.** { *; }
-keepclassmembers class io.flutter.plugins.packageinfo.** { *; }

# Path provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
