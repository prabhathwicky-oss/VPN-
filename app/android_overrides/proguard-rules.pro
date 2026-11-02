# Keep native VPN cores and their JNI bridges (stripping them crashes the tunnel).
-keep class com.wireguard.** { *; }
-keep class libv2ray.** { *; }
-keep class go.** { *; }
-keep class dev.amirzr.** { *; }
-keep class billing.mysterium.** { *; }
-dontwarn com.wireguard.**
-dontwarn libv2ray.**
-dontwarn go.**

# Google Play Billing / Ads
-keep class com.android.vending.billing.** { *; }
-keep class com.google.android.gms.ads.** { *; }
