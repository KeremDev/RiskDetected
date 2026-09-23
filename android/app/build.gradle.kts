import java.util.Properties
import java.util.Base64
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import org.gradle.api.DefaultTask
import org.gradle.api.provider.Property
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension

plugins {
    alias(libs.plugins.android.application)
    // org.jetbrains.kotlin.android is no longer needed under AGP 9's built-in Kotlin support.
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
    alias(libs.plugins.google.services)
    alias(libs.plugins.firebase.crashlytics)
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
fun configuredValue(key: String): String =
    System.getenv(key)?.trim().orEmpty().ifEmpty { localOrEmpty(key).trim() }
fun localOrFallback(primary: String, legacy: String): String =
    configuredValue(primary).ifEmpty { configuredValue(legacy) }

val stagingSupabaseUrl = configuredValue("RD_STAGING_SUPABASE_URL")
val productionSupabaseUrl = configuredValue("RD_PRODUCTION_SUPABASE_URL")
val stagingSupabasePublishableKey = localOrFallback(
    "RD_STAGING_SUPABASE_PUBLISHABLE_KEY",
    "RD_STAGING_SUPABASE_ANON_KEY",
)
val productionSupabasePublishableKey = localOrFallback(
    "RD_PRODUCTION_SUPABASE_PUBLISHABLE_KEY",
    "RD_PRODUCTION_SUPABASE_ANON_KEY",
)
val stagingGoogleWebClientId = configuredValue("RD_STAGING_GOOGLE_WEB_CLIENT_ID")
val productionGoogleWebClientId = configuredValue("RD_PRODUCTION_GOOGLE_WEB_CLIENT_ID")
val stagingRevenueCatPublicKey = configuredValue("RD_STAGING_REVENUECAT_PUBLIC_KEY")
val productionRevenueCatPublicKey = configuredValue("RD_PRODUCTION_REVENUECAT_PUBLIC_KEY")
val stagingFirebaseProjectId = configuredValue("RD_STAGING_FIREBASE_PROJECT_ID")
val productionFirebaseProjectId = configuredValue("RD_PRODUCTION_FIREBASE_PROJECT_ID")
val buildSha = configuredValue("RD_BUILD_SHA").ifEmpty { "local" }
val expectedProductionSupabaseUrl = "https://ppcrzemgiztzcgddbins.supabase.co"
val productionGoogleServicesFile = file("google-services.json")
val productionGoogleServicesText = productionGoogleServicesFile.takeIf(File::isFile)?.readText().orEmpty()
val productionGoogleServicesProjectId =
    Regex("\\\"project_id\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
        .find(productionGoogleServicesText)
        ?.groupValues
        ?.get(1)
        .orEmpty()
val productionGoogleServicesProjectNumber =
    Regex("\\\"project_number\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
        .find(productionGoogleServicesText)
        ?.groupValues
        ?.get(1)
        .orEmpty()
val productionGoogleServicesWebClientIds =
    Regex(
        "\\\"client_id\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"\\s*,\\s*\\\"client_type\\\"\\s*:\\s*3",
    )
        .findAll(productionGoogleServicesText)
        .map { it.groupValues[1] }
        .toSet()
val productionGoogleServicesHasPackage = productionGoogleServicesText.contains(
    "\\\"package_name\\\"\\s*:\\s*\\\"com.riskdetectedan.app\\\"".toRegex(),
)

// Public identifiers are safe to compare in source, but release still has to receive its own
// values from the owner-controlled CI environment. These sentinels keep debug/qa fail-closed even
// in a PR job where production secrets are intentionally unavailable.
val knownProductionMarkers = setOf(
    expectedProductionSupabaseUrl,
    "200539603330-52rbngma5qs4717qnhff1rgr3pu9rv5i.apps.googleusercontent.com",
    "195728384880-hl9phpirnluits33j3lvvdfcgrlmnrbk.apps.googleusercontent.com",
    "goog_IloQRDmtxistmNayBpPfwNbIoYa",
    "riskdetected",
)

val uploadStoreFilePath = configuredValue("ANDROID_UPLOAD_STORE_FILE")
val uploadStorePassword = configuredValue("ANDROID_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = configuredValue("ANDROID_UPLOAD_KEY_ALIAS")
val uploadKeyPassword = configuredValue("ANDROID_UPLOAD_KEY_PASSWORD")
val uploadCertificateSha256 = configuredValue("ANDROID_UPLOAD_CERT_SHA256")
val releaseSigningConfigured = listOf(
    uploadStoreFilePath,
    uploadStorePassword,
    uploadKeyAlias,
    uploadKeyPassword,
    uploadCertificateSha256,
).all { it.isNotBlank() }

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
    @get:Input abstract val firebaseConfigProjectId: Property<String>
    @get:Input abstract val firebaseConfigProjectNumber: Property<String>
    @get:Input abstract val firebaseConfigWebClientIds: Property<String>
    @get:Input abstract val firebaseConfigHasReleasePackage: Property<Boolean>
    @get:Input abstract val expectedSupabaseUrl: Property<String>
    @get:Input abstract val signingConfigured: Property<Boolean>
    @get:Input abstract val signingStorePath: Property<String>
    @get:Internal abstract val signingStorePassword: Property<String>
    @get:Internal abstract val signingKeyAlias: Property<String>
    @get:Input abstract val signingCertificateSha256: Property<String>
    @get:Input abstract val legalBundleApproved: Property<Boolean>
    @get:Input abstract val legalPublicUrlsVerified: Property<Boolean>

    @TaskAction
    fun verify() {
        check(supabaseUrl.get().startsWith("https://")) {
            "Release requires a configured HTTPS production Supabase URL."
        }
        check(supabaseUrl.get() == expectedSupabaseUrl.get()) {
            "Release Supabase URL does not match the approved production project."
        }
        check(supabasePublishableKey.get().isNotBlank()) {
            "Release requires a production Supabase publishable key."
        }
        check(googleWebClientId.get().isNotBlank()) {
            "Release requires the production Google OAuth web client id."
        }
        check(googleWebClientId.get().endsWith(".apps.googleusercontent.com")) {
            "Release Google OAuth value is not a web client id."
        }
        val firebaseWebClientIds = firebaseConfigWebClientIds.get()
            .split(',')
            .map(String::trim)
            .filter(String::isNotBlank)
            .toSet()
        check(googleWebClientId.get() in firebaseWebClientIds) {
            "Release Google OAuth web client id is not registered in app/google-services.json. " +
                "Android and server OAuth clients must belong to the same Google Cloud project."
        }
        check(
            firebaseConfigProjectNumber.get().isNotBlank() &&
                googleWebClientId.get().startsWith("${firebaseConfigProjectNumber.get()}-"),
        ) {
            "Release Google OAuth web client id does not belong to the Firebase project number."
        }
        check(revenueCatPublicKey.get().isNotBlank()) {
            "Release requires the production RevenueCat public key."
        }
        check(revenueCatPublicKey.get().startsWith("goog_")) {
            "Release RevenueCat key must be the Google Play public SDK key."
        }
        check(firebaseProjectId.get().isNotBlank()) {
            "Release requires the production Firebase project id."
        }
        check(firebaseProjectId.get() == firebaseConfigProjectId.get()) {
            "Release Firebase project id does not match app/google-services.json."
        }
        check(firebaseConfigHasReleasePackage.get()) {
            "Release google-services.json does not contain com.riskdetectedan.app."
        }
        check(signingConfigured.get()) {
            "Release requires all ANDROID_UPLOAD_* signing values. The upload keystore must stay outside the repository."
        }
        check(File(signingStorePath.get()).isFile) {
            "ANDROID_UPLOAD_STORE_FILE must point to an existing upload keystore."
        }
        val storeFile = File(signingStorePath.get())
        val certificate = listOf(KeyStore.getDefaultType(), "PKCS12", "JKS")
            .distinct()
            .firstNotNullOfOrNull { type ->
                runCatching {
                    val keyStore = KeyStore.getInstance(type)
                    storeFile.inputStream().use {
                        keyStore.load(it, signingStorePassword.get().toCharArray())
                    }
                    keyStore.getCertificate(signingKeyAlias.get())
                }.getOrNull()
            }
            ?: error("Upload keystore alias/password could not be verified.")
        val actualFingerprint = MessageDigest.getInstance("SHA-256")
            .digest(certificate.encoded)
            .joinToString("") { "%02x".format(it) }
        val expectedFingerprint = signingCertificateSha256.get()
            .replace(":", "")
            .lowercase()
        check(expectedFingerprint.matches(Regex("[a-f0-9]{64}")) && actualFingerprint == expectedFingerprint) {
            "Upload certificate SHA-256 does not match the owner-approved fingerprint."
        }
        check(legalBundleApproved.get()) {
            "Release requires an owner-approved Android legal bundle."
        }
        check(legalPublicUrlsVerified.get()) {
            "Release requires published and verified /gizlilik and /hesap-silme URLs."
        }
    }
}

abstract class VerifyAndroidLegalBundleTask : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val legalAssetsDirectory: DirectoryProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val approvalRecord: RegularFileProperty

    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val englishLegalDirectory: DirectoryProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val englishApprovalRecord: RegularFileProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val legalMigration: RegularFileProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val releasePolicyFunction: RegularFileProperty

    private fun File.sha256Hex(): String = MessageDigest.getInstance("SHA-256")
        .digest(readBytes())
        .joinToString("") { "%02x".format(it) }

    @TaskAction
    fun verify() {
        val legalAssetsDir = legalAssetsDirectory.get().asFile
        val manifest = legalAssetsDir.resolve("manifest.json").readText()
        check(Regex("\"release_status\"\\s*:\\s*\"(approved|pending_owner_approval)\"").containsMatchIn(manifest))
        check(Regex("\"counsel_review_status\"\\s*:\\s*\"(approved|pending)\"").containsMatchIn(manifest))
        check(manifest.contains("https://riskdetected.com/gizlilik"))
        check(manifest.contains("https://riskdetected.com/hesap-silme"))

        val approvalPath = Regex("\"counsel_approval_record_path\"\\s*:\\s*\"([^\"]+)\"")
            .find(manifest)?.groupValues?.get(1)
            ?: error("Android legal approval record path is missing.")
        val approvalHash = Regex("\"counsel_approval_record_sha256\"\\s*:\\s*\"([a-f0-9]{64})\"")
            .find(manifest)?.groupValues?.get(1)
            ?: error("Android legal approval record checksum is missing.")
        val approvalFile = approvalRecord.get().asFile
        check(approvalPath.endsWith(approvalFile.name) && approvalFile.sha256Hex() == approvalHash) {
            "Android legal approval record checksum mismatch."
        }

        val entries = Regex(
            "\"kind\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?" +
                "\"version\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?" +
                "\"path\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?" +
                "\"hash\"\\s*:\\s*\"([a-f0-9]{64})\"",
        ).findAll(manifest).map { match ->
            val kind = match.groupValues[1]
            val version = match.groupValues[2]
            val document = legalAssetsDir.resolve(match.groupValues[3])
            val expectedHash = match.groupValues[4]
            check(document.isFile && document.sha256Hex() == expectedHash) {
                "Android legal document checksum mismatch: ${document.name}"
            }
            "$kind|$version|$expectedHash"
        }.toList()
        check(entries.size == 4) { "Android legal manifest must contain exactly four documents." }

        val acceptanceChecksum = MessageDigest.getInstance("SHA-256")
            .digest(entries.sorted().joinToString("\n").toByteArray())
            .joinToString("") { "%02x".format(it) }
        val backendFiles = listOf(
            legalMigration.get().asFile,
            releasePolicyFunction.get().asFile,
        )
        check(backendFiles.all { it.readText().contains(acceptanceChecksum) }) {
            "Android legal acceptance checksum is not synchronized with backend policy."
        }

        val englishLegalDir = englishLegalDirectory.get().asFile
        val englishManifest = englishLegalDir.resolve("en/manifest.json").readText()
        check(Regex("\"release_status\"\\s*:\\s*\"approved\"").containsMatchIn(englishManifest))
        check(Regex("\"counsel_review_status\"\\s*:\\s*\"approved\"").containsMatchIn(englishManifest))
        check(englishManifest.contains("https://riskdetected.com/legal-documents/en/Terms-of-Use.md"))
        check(englishManifest.contains("https://riskdetected.com/legal-documents/en/Privacy-Policy.md"))
        check(englishManifest.contains("https://riskdetected.com/legal-documents/en/AI-and-Data-Processing-Notice.md"))

        val englishApprovalPath = Regex("\"counsel_approval_record_path\"\\s*:\\s*\"([^\"]+)\"")
            .find(englishManifest)?.groupValues?.get(1)
            ?: error("English legal approval record path is missing.")
        val englishApprovalHash = Regex("\"counsel_approval_record_sha256\"\\s*:\\s*\"([a-f0-9]{64})\"")
            .find(englishManifest)?.groupValues?.get(1)
            ?: error("English legal approval record checksum is missing.")
        val englishApprovalFile = englishApprovalRecord.get().asFile
        check(englishApprovalPath.endsWith(englishApprovalFile.name) && englishApprovalFile.sha256Hex() == englishApprovalHash) {
            "English legal approval record checksum mismatch."
        }

        val englishEntries = Regex(
            "\"kind\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?" +
                "\"version\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?" +
                "\"path\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?" +
                "\"hash\"\\s*:\\s*\"([a-f0-9]{64})\"",
        ).findAll(englishManifest).map { match ->
            val kind = match.groupValues[1]
            val version = match.groupValues[2]
            val document = englishLegalDir.resolve(match.groupValues[3])
            val expectedHash = match.groupValues[4]
            check(document.isFile && document.sha256Hex() == expectedHash) {
                "English legal document checksum mismatch: ${document.name}"
            }
            "$kind|$version|$expectedHash"
        }.toList()
        check(englishEntries.size == 3) { "English legal manifest must contain exactly three documents." }
        val englishAcceptanceChecksum = MessageDigest.getInstance("SHA-256")
            .digest(englishEntries.sorted().joinToString("\n").toByteArray())
            .joinToString("") { "%02x".format(it) }
        check(releasePolicyFunction.get().asFile.readText().contains(englishAcceptanceChecksum)) {
            "English legal acceptance checksum is not synchronized with the release policy function."
        }
    }
}

val legalAssetsDir = file("src/main/assets/legal")
val legalManifestFile = legalAssetsDir.resolve("manifest.json")
val legalManifestText = legalManifestFile.readText()
val englishLegalAssetsDir = rootProject.file("../App/LegalDocuments")
val englishLegalManifestText = englishLegalAssetsDir.resolve("en/manifest.json").readText()
val androidLegalBundleApproved =
    Regex("\"release_status\"\\s*:\\s*\"approved\"").containsMatchIn(legalManifestText) &&
        Regex("\"counsel_review_status\"\\s*:\\s*\"approved\"").containsMatchIn(legalManifestText) &&
        Regex("\"release_status\"\\s*:\\s*\"approved\"").containsMatchIn(englishLegalManifestText) &&
        Regex("\"counsel_review_status\"\\s*:\\s*\"approved\"").containsMatchIn(englishLegalManifestText)
val androidLegalPublicUrlsVerified =
    !Regex("\"public_urls_verified_at\"\\s*:\\s*null").containsMatchIn(legalManifestText) &&
        !Regex("\"public_urls_verified_at\"\\s*:\\s*null").containsMatchIn(englishLegalManifestText)
val metaEventsTransportSmokeMode =
    providers.gradleProperty("rdMetaEventsTransportSmoke").orNull == "true"

android {
    namespace = "com.riskdetectedan.app"
    compileSdk = 37
    testBuildType = if (metaEventsTransportSmokeMode) "metaSmoke" else "debug"

    // Reuse the counsel-approved English legal set that iOS ships. Android keeps its own
    // Turkish bundle under app/src/main/assets/legal and reads this shared set under /en.
    sourceSets.getByName("main").assets.srcDir(rootProject.file("../App/LegalDocuments"))
    // Bundle the shared, read-only Work Permit Word catalog.
    sourceSets.getByName("main").assets.srcDir(rootProject.file("../App/WorkPermitAssets"))

    defaultConfig {
        applicationId = "com.riskdetectedan.app"
        minSdk = 26
        targetSdk = 37
        versionCode = 14
        versionName = "2.0.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["facebookSdkAutoInitEnabled"] = "false"

        ndk {
            debugSymbolLevel = "SYMBOL_TABLE"
        }
    }

    signingConfigs {
        create("upload") {
            if (releaseSigningConfigured) {
                storeFile = file(uploadStoreFilePath)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    // Master plan §9.1 variant table, DEC-01 package adopted instead of the plan's placeholder.
    // debug/qa -> staging backend, release -> production — enforced by which BuildConfig
    // constants exist per build type, never by a runtime switch a release binary could flip.
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "false"
            manifestPlaceholders["firebaseCrashlyticsCollectionEnabled"] = "false"
            manifestPlaceholders["facebookSdkAutoInitEnabled"] = "false"
            buildConfigField("String", "ENVIRONMENT_NAME", "staging".asBuildConfigString())
            buildConfigField("boolean", "NOVA_PILOT", "false")
            buildConfigField("String", "SUPABASE_URL", stagingSupabaseUrl.asBuildConfigString())
            buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", stagingSupabasePublishableKey.asBuildConfigString())
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", stagingGoogleWebClientId.asBuildConfigString())
            buildConfigField("String", "REVENUECAT_PUBLIC_KEY", stagingRevenueCatPublicKey.asBuildConfigString())
            buildConfigField("String", "REVENUECAT_OFFERING_ID", "qa_test_store".asBuildConfigString())
            buildConfigField("String", "FIREBASE_PROJECT_ID", stagingFirebaseProjectId.asBuildConfigString())
            buildConfigField("boolean", "CRASHLYTICS_ENABLED", "false")
            buildConfigField("String", "BUILD_SHA", buildSha.asBuildConfigString())
            configure<CrashlyticsExtension> {
                mappingFileUploadEnabled = false
            }
        }
        if (metaEventsTransportSmokeMode) {
            create("metaSmoke") {
                initWith(getByName("debug"))
                // Meta Test Events matches the package registered in the Meta app. This
                // opt-in, local-only variant keeps debug behavior but uses that exact package.
                applicationIdSuffix = ""
                versionNameSuffix = "-meta-smoke"
                matchingFallbacks += listOf("debug")
            }
        }
        // The Android counterpart of the iOS OSGB pilot bundle: staging backend, the
        // NOVA expert product instead of MainShell. It keeps the debug package so it
        // uses the Firebase client already registered for staging; a separate
        // `.osgbpilot` package needs its own Firebase registration first.
        create("osgbPilot") {
            initWith(getByName("debug"))
            versionNameSuffix = "-osgbpilot"
            matchingFallbacks += listOf("debug")
            buildConfigField("boolean", "NOVA_PILOT", "true")
        }
        create("qa") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".qa"
            versionNameSuffix = "-qa"
            // RevenueCat's Test Store intentionally aborts non-debuggable processes. QA uses
            // the isolated staging Test Store key, so it must stay debuggable; release remains
            // non-debuggable and is independently forced to use the Google Play public key.
            isDebuggable = true
            isMinifyEnabled = false
            isShrinkResources = false
            matchingFallbacks += listOf("debug")
            val qaCrashlyticsEnabled = stagingFirebaseProjectId.isNotBlank()
            manifestPlaceholders["firebaseCrashlyticsCollectionEnabled"] = qaCrashlyticsEnabled.toString()
            buildConfigField("boolean", "CRASHLYTICS_ENABLED", qaCrashlyticsEnabled.toString())
            configure<CrashlyticsExtension> {
                mappingFileUploadEnabled = qaCrashlyticsEnabled
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            manifestPlaceholders["firebaseMessagingAutoInitEnabled"] = "true"
            manifestPlaceholders["firebaseCrashlyticsCollectionEnabled"] = "true"
            manifestPlaceholders["facebookSdkAutoInitEnabled"] = "true"
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("upload")
            }
            buildConfigField("String", "ENVIRONMENT_NAME", "production".asBuildConfigString())
            buildConfigField("boolean", "NOVA_PILOT", "false")
            buildConfigField("String", "SUPABASE_URL", productionSupabaseUrl.asBuildConfigString())
            buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", productionSupabasePublishableKey.asBuildConfigString())
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", productionGoogleWebClientId.asBuildConfigString())
            buildConfigField("String", "REVENUECAT_PUBLIC_KEY", productionRevenueCatPublicKey.asBuildConfigString())
            buildConfigField("String", "REVENUECAT_OFFERING_ID", "default".asBuildConfigString())
            buildConfigField("String", "FIREBASE_PROJECT_ID", productionFirebaseProjectId.asBuildConfigString())
            buildConfigField("boolean", "CRASHLYTICS_ENABLED", "true")
            buildConfigField("String", "BUILD_SHA", buildSha.asBuildConfigString())
            configure<CrashlyticsExtension> {
                mappingFileUploadEnabled = true
            }
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
    productionSupabasePublishableKey,
    productionGoogleWebClientId,
    productionRevenueCatPublicKey,
    productionFirebaseProjectId,
).filter { it.isNotBlank() }.toSet() + knownProductionMarkers
mapOf(
    "staging Supabase URL" to stagingSupabaseUrl,
    "staging Supabase key" to stagingSupabasePublishableKey,
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
    val expectedPackage = if (variant == "debug") {
        "com.riskdetectedan.app.debug"
    } else {
        "com.riskdetectedan.app.qa"
    }
    check(
        projectId.isNotBlank() &&
            projectId != productionFirebaseProjectId &&
            projectId !in knownProductionMarkers,
    ) {
        "$variant google-services.json resolves to the production Firebase project."
    }
    if (stagingFirebaseProjectId.isNotBlank()) {
        check(projectId == stagingFirebaseProjectId) {
            "$variant google-services.json does not match RD_STAGING_FIREBASE_PROJECT_ID."
        }
    }
    check(firebaseConfig.readText().contains(
        "\\\"package_name\\\"\\s*:\\s*\\\"${Regex.escape(expectedPackage)}\\\"".toRegex(),
    )) {
        "$variant google-services.json does not contain $expectedPackage."
    }
}

val verifyEnvironmentIsolation = tasks.register("verifyEnvironmentIsolation") {
    group = "verification"
    description = "Fails when a non-release variant can resolve production service configuration."
}

val verifyAndroidLegalBundle = tasks.register<VerifyAndroidLegalBundleTask>("verifyAndroidLegalBundle") {
    group = "verification"
    description = "Verifies Android-only legal document, approval and backend policy checksums."
    legalAssetsDirectory.set(layout.projectDirectory.dir("src/main/assets/legal"))
    approvalRecord.set(rootProject.layout.projectDirectory.file("../docs/android/ANDROID_LEGAL_APPROVAL_RECORD_2026-08-09.json"))
    englishLegalDirectory.set(rootProject.layout.projectDirectory.dir("../App/LegalDocuments"))
    englishApprovalRecord.set(rootProject.layout.projectDirectory.file("../docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-09-08_META.json"))
    legalMigration.set(rootProject.layout.projectDirectory.file("../supabase/migrations/20260809184500_android_legal_update_policy.sql"))
    releasePolicyFunction.set(rootProject.layout.projectDirectory.file("../supabase/functions/app-release-policy/index.ts"))
}

val verifyAndroidLocalization = tasks.register<Exec>("verifyAndroidLocalization") {
    group = "verification"
    description = "Verifies complete, current English Android resources and printf placeholders."
    workingDir(rootProject.projectDir)
    commandLine("python3", "scripts/generate_android_english_resources.py", "--check")
}

val verifyReleaseEnvironment = tasks.register<VerifyReleaseEnvironmentTask>("verifyReleaseEnvironment") {
    group = "verification"
    description = "Fails closed when a release service configuration is absent."
    supabaseUrl.set(productionSupabaseUrl)
    supabasePublishableKey.set(productionSupabasePublishableKey)
    googleWebClientId.set(productionGoogleWebClientId)
    revenueCatPublicKey.set(productionRevenueCatPublicKey)
    firebaseProjectId.set(productionFirebaseProjectId)
    firebaseConfigProjectId.set(productionGoogleServicesProjectId)
    firebaseConfigProjectNumber.set(productionGoogleServicesProjectNumber)
    firebaseConfigWebClientIds.set(productionGoogleServicesWebClientIds.sorted().joinToString(","))
    firebaseConfigHasReleasePackage.set(productionGoogleServicesHasPackage)
    expectedSupabaseUrl.set(expectedProductionSupabaseUrl)
    signingConfigured.set(releaseSigningConfigured)
    signingStorePath.set(uploadStoreFilePath)
    signingStorePassword.set(uploadStorePassword)
    signingKeyAlias.set(uploadKeyAlias)
    signingCertificateSha256.set(uploadCertificateSha256)
    legalBundleApproved.set(androidLegalBundleApproved)
    legalPublicUrlsVerified.set(androidLegalPublicUrlsVerified)
}

tasks.named("preBuild").configure {
    dependsOn(verifyEnvironmentIsolation)
    dependsOn(verifyAndroidLegalBundle)
    dependsOn(verifyAndroidLocalization)
}
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
    implementation(project(":feature:nova"))

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
    implementation(libs.firebase.crashlytics)
    implementation(libs.install.referrer)
    implementation(libs.play.review)
    implementation(libs.play.app.update)
    implementation(libs.play.app.update.ktx)
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
    androidTestImplementation(libs.facebook.core)
    androidTestImplementation("androidx.localbroadcastmanager:localbroadcastmanager:1.0.0")
}
