pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "riskdetected-android"

include(":app")
include(":core:common")
include(":core:data")
include(":core:designsystem")
include(":core:testing")
// Standalone on-device contract harness; never a dependency of :app.
include(":isg-contract-tests")
// Offline visual QA host; never a dependency of :app or a store variant.
include(":isg-design-preview")
// Isolated emulator-only persistence proof; never a production app dependency.
include(":isg-journal-check")
// Real native SDK acceptance against an explicit loopback-only synthetic fixture.
include(":isg-native-check")
include(":feature:onboarding")
include(":feature:capture")
include(":feature:analysis")
include(":feature:reports")
include(":feature:profile")
include(":feature:paywall")
// The NOVA expert product (iOS NovaPilotRoot parity); mounted only in the pilot build type.
include(":feature:nova")
