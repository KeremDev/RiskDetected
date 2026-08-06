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
include(":feature:onboarding")
include(":feature:capture")
include(":feature:analysis")
include(":feature:reports")
include(":feature:profile")
include(":feature:paywall")
