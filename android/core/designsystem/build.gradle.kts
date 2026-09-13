plugins {
    alias(libs.plugins.android.library)
    // org.jetbrains.kotlin.android is no longer needed under AGP 9's built-in Kotlin support.
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.riskdetectedan.core.designsystem"
    compileSdk = 37

    defaultConfig {
        minSdk = 26
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.serialization.json)
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.junit)
    testImplementation(libs.androidx.espresso.core)
    debugImplementation(libs.compose.ui.test.manifest)
    implementation(libs.androidx.activity.compose)
}

tasks.withType<org.gradle.api.tasks.testing.Test>().configureEach {
    inputs.file(rootProject.layout.projectDirectory.file("../contracts/isg/v1/fixtures/nova-company-list.json"))
        .withPropertyName("isgNovaCompanyListCorpus")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.file(rootProject.layout.projectDirectory.file("../contracts/isg/v1/fixtures/nova-session-host.json"))
        .withPropertyName("isgNovaSessionHostCorpus")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(rootProject.layout.projectDirectory.dir("../contracts/isg/v1/design"))
        .withPropertyName("isgNovaDesignCorpus")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.file(rootProject.layout.projectDirectory.file("../contracts/isg/v1/fixtures/nova-navigation.json"))
        .withPropertyName("isgNovaNavigationCorpus")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}
