# Flutter ProGuard / R8 Keep Rules for Release Mode

# Preserve essential annotations and signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep Firebase Auth, Messaging, Firestore & Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Keep Flutter Platform Channels & Embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Keep Camera & Mobile Scanner / Barcode
-keep class dev.steenbakker.mobile_scanner.** { *; }

# Keep Google ML Kit OCR & Vision
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**

# Keep Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep Bluetooth Thermal Printing & ESC POS Utils
-keep class com.print.bluetooth.thermal.** { *; }
-keep class net.posprinter.** { *; }
-dontwarn net.posprinter.**

# Keep Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Keep Java Desugaring
-keep class j$.** { *; }
