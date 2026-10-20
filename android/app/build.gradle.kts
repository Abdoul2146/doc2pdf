plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.magnatrus.doc2pdf"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by Apache POI (java.time / java.nio stream APIs) on Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.magnatrus.doc2pdf"
        // Bumped from the Flutter default (24): Apache POI's CleanerUtil and
        // log4j-api call MethodHandle.invoke, which D8 only accepts at API 26+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                "META-INF/*.kotlin_module",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // WebViewAssetLoader -> serves bundled render assets to the offscreen WebView.
    implementation("androidx.webkit:webkit:1.12.1")

    // Legacy .doc (Word 97-2003, OLE2/CFB) parsing only.
    // .docx is handled in JS by docx-preview, so poi-ooxml/xmlbeans are intentionally omitted.
    implementation("org.apache.poi:poi:5.2.5")
    implementation("org.apache.poi:poi-scratchpad:5.2.5")

    // Keep only the logging API; POI logs become no-ops on Android.
    implementation("org.apache.logging.log4j:log4j-api:2.23.1")
}

flutter {
    source = "../.."
}
