plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}
android {
    namespace = "com.riskdetectedan.isg.designpreview"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.riskdetectedan.isg.designpreview"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "qa-only"
    }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
// No release artifact or production dependency graph.
androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }
dependencies {
    implementation(project(":core:designsystem"))
    // Screens only, fed synthetic lambdas; no Hilt graph or service is started here.
    implementation(project(":feature:nova"))
    implementation(project(":core:data"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.androidx.activity.compose)
}
