# Tesseract4Android and its bundled leptonica are called through JNI, which
# looks classes, fields and methods up by name: R8 must not rename or strip
# them.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
