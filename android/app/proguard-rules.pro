# Preserve source/line metadata required for deobfuscated Firebase Crashlytics reports.
-keepattributes SourceFile,LineNumberTable

# Kotlin serialization models carry generated serializers; annotations and
# inner/enclosing metadata must remain available to their serializers under R8.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault,InnerClasses,EnclosingMethod
