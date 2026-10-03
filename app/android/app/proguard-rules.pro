# google_mlkit_text_recognition references the optional Chinese, Devanagari,
# Japanese and Korean recognisers; only the bundled Latin one ships, so R8
# must not fail on the others' absence.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit finds its component registrars by reflection; R8 (full mode)
# otherwise strips their no-argument constructors and the first
# processImage call fails with a NullPointerException (seen 2026-10-03).
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
