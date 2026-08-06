plugins {
    alias(libs.plugins.android.library)
    // org.jetbrains.kotlin.android is no longer needed under AGP 9's built-in Kotlin support.
}

android {
    namespace = "com.riskdetectedan.core.common"
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
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.android)
    // Only javax.inject (not the full Hilt/Dagger stack) — core:common stays DI-framework-light;
    // Hilt's own @Module/@InstallIn wiring lives in core:data / :app.
    api(libs.javax.inject)

    testImplementation(libs.junit)
}
