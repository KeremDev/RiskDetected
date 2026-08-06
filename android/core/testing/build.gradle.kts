plugins {
    alias(libs.plugins.android.library)
    // org.jetbrains.kotlin.android is no longer needed under AGP 9's built-in Kotlin support.
}

android {
    namespace = "com.riskdetectedan.core.testing"
    compileSdk = 37

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(libs.junit)
    api(libs.kotlinx.coroutines.test)
    api(libs.turbine)
    api(libs.mockwebserver)
    implementation(project(":core:common"))
}
