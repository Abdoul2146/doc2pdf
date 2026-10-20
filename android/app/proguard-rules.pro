# --- Apache POI -------------------------------------------------------------
# POI's optional Excel/graphics helpers reference desktop-only classes that do
# not exist on Android. The HWPF (.doc) path used here never reaches them, but
# R8 still resolves the references and aborts the build.
-dontwarn java.awt.**
-dontwarn javax.imageio.**
-dontwarn javax.swing.**
-dontwarn org.osgi.**
-dontwarn aQute.bnd.annotation.**
-dontwarn edu.umd.cs.findbugs.annotations.**

# --- log4j-api (used without log4j-core) ------------------------------------
# Keep the built-in simple-logger fallback and the ServiceLoader-discovered
# property sources so R8 does not strip classes only referenced by name.
-keep class org.apache.logging.log4j.simple.** { *; }
-keep class org.apache.logging.log4j.util.EnvironmentPropertySource { *; }
-keep class org.apache.logging.log4j.util.SystemPropertiesPropertySource { *; }
