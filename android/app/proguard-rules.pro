# Flutter 3.4x 的 Gradle 插件默认对 release 开启 R8 + shrinkResources，
# 这里补第三方 SDK 的 keep 规则（AAR 自带的 consumer 规则通常够用，此处保险起见显式声明）。
# 改动后务必用 release 包真机回归：微信登录、裁剪页(uCrop)、BLE 扫描/图传三条链路。

# 微信 OpenSDK（fluwx 依赖）：反射调用较多，混淆会导致授权回调静默失败。
-keep class com.tencent.mm.opensdk.** { *; }
-keep class com.tencent.wxop.** { *; }

# uCrop（image_cropper Android 侧）。
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# fluwx 5.x 经 package:jni（dart JNI 绑定）反射调用 Java 类，
# R8 误裁会在运行时 ClassNotFound/NoSuchMethod 直接崩进程。
-keep class com.github.dart_lang.jni.** { *; }
-dontwarn com.github.dart_lang.jni.**
