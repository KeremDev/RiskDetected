plugins { alias(libs.plugins.android.application); alias(libs.plugins.kotlin.compose) }
android {
    namespace = "com.riskdetectedan.isg.nativecheck"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.riskdetectedan.isg.nativecheck"
        minSdk = 26; targetSdk = 37; versionCode = 1; versionName = "qa-only"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    sourceSets.getByName("main").kotlin.directories.add(layout.buildDirectory.dir("generated/workspace").get().asFile.path)
}
val workspaceSource by tasks.registering(Sync::class) {
    from(rootProject.file("feature/profile/src/main/kotlin/com/riskdetectedan/feature/profile")) {
        include("NovaWorkspaceViewModel.kt", "NovaPersonnelRepositoryAdapter.kt", "NovaDirectoryRepositoryAdapter.kt", "NovaCompanyRepositoryAdapter.kt")
    }
    into(layout.buildDirectory.dir("generated/workspace"))
}
tasks.configureEach { if (name.startsWith("compile") && name.endsWith("Kotlin")) dependsOn(workspaceSource) }
androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }
dependencies {
    implementation(project(":core:data")); implementation(project(":core:common")); implementation(project(":core:designsystem"))
    implementation(libs.supabase.auth); implementation(libs.supabase.postgrest); implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.serialization.json); implementation(libs.kotlinx.coroutines.android)
    implementation(platform(libs.compose.bom)); implementation(libs.compose.material3); implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose); implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.hilt.android); implementation(libs.javax.inject)
    androidTestImplementation(platform(libs.compose.bom)); androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.junit); androidTestImplementation(libs.androidx.espresso.core)
}
