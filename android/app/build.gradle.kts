import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    // org.jetbrains.kotlin.android is no longer needed under AGP 9's built-in Kotlin support.
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
    alias(libs.plugins.google.services)
}

// google-services.json (committed — Firebase's own docs: "does not contain sensitive keys or
// secrets", same category as the RevenueCat public SDK key) covers both com.riskdetectedan.app
// (release/qa) and com.riskdetectedan.app.debug as two `client` entries in one file; the
// google-services plugin picks the matching entry per applicationId at build time, no
// per-variant file needed. firebase-crashlytics still isn't added — DEC-06/Faz 7 scope, separate
// from FCM.

// Per-machine secrets (staging/production Supabase URL+anon key) live in local.properties,
// which is gitignored (android/.gitignore) — never in gradle.properties or committed source.
// Empty until DEC-12's staging project is provisioned and this file is filled in locally.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun localOrEmpty(key: String): String = localProperties.getProperty(key, "")

android {
    namespace = "com.riskdetectedan.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.riskdetectedan.app"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "1.5.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // Master plan §9.1 variant table, DEC-01 package adopted instead of the plan's placeholder.
    // debug/qa -> staging backend, release -> production — enforced by which BuildConfig
    // constants exist per build type, never by a runtime switch a release binary could flip.
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            buildConfigField("String", "ENVIRONMENT_NAME", "\"staging\"")
            buildConfigField("String", "SUPABASE_URL", "\"${localOrEmpty("RD_STAGING_SUPABASE_URL")}\"")
            buildConfigField("String", "SUPABASE_ANON_KEY", "\"${localOrEmpty("RD_STAGING_SUPABASE_ANON_KEY")}\"")
        }
        create("qa") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".qa"
            versionNameSuffix = "-qa"
            isDebuggable = false
            matchingFallbacks += listOf("debug")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "ENVIRONMENT_NAME", "\"production\"")
            buildConfigField("String", "SUPABASE_URL", "\"${localOrEmpty("RD_PRODUCTION_SUPABASE_URL")}\"")
            buildConfigField("String", "SUPABASE_ANON_KEY", "\"${localOrEmpty("RD_PRODUCTION_SUPABASE_ANON_KEY")}\"")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(project(":core:common"))
    implementation(project(":core:data"))
    implementation(project(":core:designsystem"))
    implementation(project(":feature:onboarding"))
    implementation(project(":feature:capture"))
    implementation(project(":feature:analysis"))
    implementation(project(":feature:reports"))
    implementation(project(":feature:profile"))
    implementation(project(":feature:paywall"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.work.runtime.ktx)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    implementation(libs.hilt.android)
    implementation(libs.hilt.navigation.compose)
    ksp(libs.hilt.android.compiler)

    implementation(libs.kotlinx.serialization.json)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.kotlinx.coroutines.play.services)

    testImplementation(project(":core:testing"))
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
