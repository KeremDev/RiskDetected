plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.riskdetectedan.isg.contracttests"
    compileSdk = 37
    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets {
        // Compile the actual production parser, without core:data's Auth,
        // billing, telemetry, Hilt or networking dependency graph.
        getByName("main").kotlin.directories.add("../core/data/src/main/kotlin/com/riskdetectedan/core/data/isg")
        getByName("androidTest").assets.directories.add("../../contracts/isg/v1/fixtures")
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    // Already cached/pinned by existing Android test toolchain; no SDK upgrade.
    androidTestImplementation("androidx.test:runner:1.7.0")
}
