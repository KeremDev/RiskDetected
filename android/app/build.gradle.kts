import java.util.Properties
import java.util.Base64
import org.gradle.api.DefaultTask
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.TaskAction
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi

plugins {
    alias(libs.plugins.android.application)
    // org.jetbrains.kotlin.android is no longer needed under AGP 9's built-in Kotlin support.
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
    alias(libs.plugins.google.services)
    alias(libs.plugins.roborazzi)
}

// The root google-services.json is production-only. debug/qa have variant-local, deliberately
// unconfigured placeholders so a developer build can never mint an FCM token in the production
// Firebase project. Replace those files with real staging Firebase configs when the console-side
// project is provisioned; until then FCM auto-init and token registration stay disabled.

// Per-machine configuration (staging/production Supabase URL+publishable key and public OAuth /
// billing identifiers) lives in local.properties,
// which is gitignored (android/.gitignore) — never in gradle.properties or committed source.
// Empty until DEC-12's staging project is provisioned and this file is filled in locally.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun localOrEmpty(key: String): String = localProperties.getProperty(key, "")
fun localOrFallback(primary: String, legacy: String): String =
    localOrEmpty(primary).ifEmpty { localOrEmpty(legacy) }

val stagingSupabaseUrl = localOrEmpty("RD_STAGING_SUPABASE_URL")
val productionSupabaseUrl = localOrEmpty("RD_PRODUCTION_SUPABASE_URL")
val stagingSupabasePublishableKey = localOrFallback(
    "RD_STAGING_SUPABASE_PUBLISHABLE_KEY",
    "RD_STAGING_SUPABASE_ANON_KEY",
)
val productionSupabasePublishableKey = localOrFallback(
    "RD_PRODUCTION_SUPABASE_PUBLISHABLE_KEY",
    "RD_PRODUCTION_SUPABASE_ANON_KEY",
)
val stagingGoogleWebClientId = localOrEmpty("RD_STAGING_GOOGLE_WEB_CLIENT_ID")
val productionGoogleWebClientId = localOrEmpty("RD_PRODUCTION_GOOGLE_WEB_CLIENT_ID")
    .ifEmpty { "200539603330-52rbngma5qs4717qnhff1rgr3pu9rv5i.apps.googleusercontent.com" }
val stagingRevenueCatPublicKey = localOrEmpty("RD_STAGING_REVENUECAT_PUBLIC_KEY")
val productionRevenueCatPublicKey = localOrEmpty("RD_PRODUCTION_REVENUECAT_PUBLIC_KEY")
    .ifEmpty { "goog_IloQRDmtxistmNayBpPfwNbIoYa" }
val stagingFirebaseProjectId = localOrEmpty("RD_STAGING_FIREBASE_PROJECT_ID")
val productionFirebaseProjectId = localOrEmpty("RD_PRODUCTION_FIREBASE_PROJECT_ID")
    .ifEmpty { "riskdetected" }

fun String.asBuildConfigString(): String = "\"${replace("\\", "\\\\").replace("\"", "\\\"")}\""

fun apiKeyRole(key: String): String? {
    if (key.startsWith("sb_secret_")) return "secret"
    if (key.count { it == '.' } != 2) return null
    return runCatching {
        val payload = String(Base64.getUrlDecoder().decode(key.split('.')[1]))
        Regex("\\\"role\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"").find(payload)?.groupValues?.get(1)
    }.getOrNull()
}

fun verifyPublicClientKey(label: String, key: String) {
    val role = apiKeyRole(key)
    check(role != "service_role" && role != "secret") {
        "$label must be a Supabase publishable/anon client key, never a service-role or secret key."
    }
}

fun verifyDistinctWhenConfigured(label: String, staging: String, production: String) {
    if (staging.isNotBlank() && production.isNotBlank()) {
        check(staging != production) { "$label staging and production values must be different." }
    }
}

abstract class VerifyReleaseEnvironmentTask : DefaultTask() {
    @get:Input abstract val supabaseUrl: Property<String>
    @get:Input abstract val supabasePublishableKey: Property<String>
    @get:Input abstract val googleWebClientId: Property<String>
    @get:Input abstract val revenueCatPublicKey: Property<String>
    @get:Input abstract val firebaseProjectId: Property<String>

    @TaskAction
    fun verify() {
        check(supabaseUrl.get().startsWith("https://")) {
            "Release requires a configured HTTPS production Supabase URL."
        }
        check(supabasePublishableKey.get().isNotBlank()) {
            "Release requires a production Supabase publishable key."
        }
        check(googleWebClientId.get().isNotBlank()) {
            "Release requires the production Google OAuth web client id."
        }
        check(revenueCatPublicKey.get().isNotBlank()) {
            "Release requires the production RevenueCat public key."
        }
        check(firebaseProjectId.get().isNotBlank()) {
            "Release requires the production Firebase project id."
        }
    }
}

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
            manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "false"
            buildConfigField("String", "ENVIRONMENT_NAME", "staging".asBuildConfigString())
            buildConfigField("String", "SUPABASE_URL", stagingSupabaseUrl.asBuildConfigString())
            buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", stagingSupabasePublishableKey.asBuildConfigString())
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", stagingGoogleWebClientId.asBuildConfigString())
            buildConfigField("String", "REVENUECAT_PUBLIC_KEY", stagingRevenueCatPublicKey.asBuildConfigString())
            buildConfigField("String", "FIREBASE_PROJECT_ID", stagingFirebaseProjectId.asBuildConfigString())
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
            manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "true"
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "ENVIRONMENT_NAME", "production".asBuildConfigString())
            buildConfigField("String", "SUPABASE_URL", productionSupabaseUrl.asBuildConfigString())
            buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", productionSupabasePublishableKey.asBuildConfigString())
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", productionGoogleWebClientId.asBuildConfigString())
            buildConfigField("String", "REVENUECAT_PUBLIC_KEY", productionRevenueCatPublicKey.asBuildConfigString())
            buildConfigField("String", "FIREBASE_PROJECT_ID", productionFirebaseProjectId.asBuildConfigString())
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

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.systemProperties["robolectric.pixelCopyRenderMode"] = "hardware"
            }
        }
    }
}

roborazzi {
    outputDir.set(file("src/test/screenshots"))
    @OptIn(ExperimentalRoborazziApi::class)
    separateOutputDirs.set(true)
}

verifyPublicClientKey("Staging Supabase key", stagingSupabasePublishableKey)
verifyPublicClientKey("Production Supabase key", productionSupabasePublishableKey)
verifyDistinctWhenConfigured("Supabase URL", stagingSupabaseUrl, productionSupabaseUrl)
verifyDistinctWhenConfigured("Google web client", stagingGoogleWebClientId, productionGoogleWebClientId)
verifyDistinctWhenConfigured("RevenueCat public key", stagingRevenueCatPublicKey, productionRevenueCatPublicKey)
verifyDistinctWhenConfigured("Firebase project", stagingFirebaseProjectId, productionFirebaseProjectId)

val productionMarkers = listOf(
    productionSupabaseUrl,
    productionGoogleWebClientId,
    productionRevenueCatPublicKey,
    productionFirebaseProjectId,
).filter { it.isNotBlank() }.toSet()
mapOf(
    "staging Supabase URL" to stagingSupabaseUrl,
    "staging Google OAuth client" to stagingGoogleWebClientId,
    "staging RevenueCat key" to stagingRevenueCatPublicKey,
    "staging Firebase project" to stagingFirebaseProjectId,
).forEach { (label, value) ->
    check(value.isBlank() || value !in productionMarkers) {
        "$label resolves to a production identifier; debug/qa builds are blocked."
    }
}
listOf("debug", "qa").forEach { variant ->
    val firebaseConfig = file("src/$variant/google-services.json")
    check(firebaseConfig.isFile) {
        "$variant must provide a variant-local google-services.json."
    }
    val projectId = Regex("\\\"project_id\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
        .find(firebaseConfig.readText())
        ?.groupValues
        ?.get(1)
        .orEmpty()
    check(projectId.isNotBlank() && projectId != productionFirebaseProjectId) {
        "$variant google-services.json resolves to the production Firebase project."
    }
}

val verifyEnvironmentIsolation = tasks.register("verifyEnvironmentIsolation") {
    group = "verification"
    description = "Fails when a non-release variant can resolve production service configuration."
}

val verifyReleaseEnvironment = tasks.register<VerifyReleaseEnvironmentTask>("verifyReleaseEnvironment") {
    group = "verification"
    description = "Fails closed when a release service configuration is absent."
    supabaseUrl.set(productionSupabaseUrl)
    supabasePublishableKey.set(productionSupabasePublishableKey)
    googleWebClientId.set(productionGoogleWebClientId)
    revenueCatPublicKey.set(productionRevenueCatPublicKey)
    firebaseProjectId.set(productionFirebaseProjectId)
}

tasks.named("preBuild").configure { dependsOn(verifyEnvironmentIsolation) }
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyReleaseEnvironment)
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
    // Debug-only E2E session bootstrap. This dependency and its Activity never enter qa/release.
    debugImplementation(libs.supabase.auth)

    implementation(libs.hilt.android)
    implementation(libs.hilt.navigation.compose)
    ksp(libs.hilt.android.compiler)

    implementation(libs.kotlinx.serialization.json)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.kotlinx.coroutines.play.services)

    testImplementation(project(":core:testing"))
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.compose.ui.test.manifest)
    testImplementation(libs.androidx.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
