# kotlinx.serialization: keep generated serializers for @Serializable classes
-keepattributes *Annotation*, InnerClasses
-keepclassmembers @kotlinx.serialization.Serializable class com.npetillo.fedsmokertv.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.npetillo.fedsmokertv.**$$serializer { *; }
