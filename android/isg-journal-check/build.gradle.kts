plugins { alias(libs.plugins.android.application) }
android {
    namespace = "com.riskdetectedan.isg.journalcheck"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.riskdetectedan.isg.journalcheck"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "qa-only"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    sourceSets.getByName("main").kotlin.directories.add(layout.buildDirectory.dir("generated/journal").get().asFile.path)
}
// A generated build copy of exactly one actual source, not a handwritten test implementation.
val journalSource by tasks.registering(Sync::class) {
    from(rootProject.file("core/data/src/main/kotlin/com/riskdetectedan/core/data/company/PersonnelPendingStorage.kt"))
    into(layout.buildDirectory.dir("generated/journal"))
}
tasks.configureEach { if (name.startsWith("compile") && name.endsWith("Kotlin")) dependsOn(journalSource) }
androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }
dependencies {
    compileOnly(libs.hilt.android) { isTransitive = false }
    compileOnly("javax.inject:javax.inject:1")
}
