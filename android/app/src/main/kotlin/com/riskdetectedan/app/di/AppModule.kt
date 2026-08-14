package com.riskdetectedan.app.di

import com.riskdetectedan.app.BuildConfig
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironment
import com.riskdetectedan.core.common.RdEnvironmentConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * The only place in the app that reads [BuildConfig] fields — everything downstream (`core:data`
 * and below) only ever sees [RdEnvironmentConfig]. This is what makes the master plan §9.1
 * build-time isolation real: swap this file's inputs and nothing else in the dependency graph
 * can accidentally point a release binary at staging or vice versa.
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideRdEnvironmentConfig(): RdEnvironmentConfig = RdEnvironmentConfig(
        environment = if (BuildConfig.ENVIRONMENT_NAME == "production") {
            RdEnvironment.Production
        } else {
            RdEnvironment.Staging
        },
        supabaseUrl = BuildConfig.SUPABASE_URL,
        supabasePublishableKey = BuildConfig.SUPABASE_PUBLISHABLE_KEY,
        appVersionName = BuildConfig.VERSION_NAME,
        appVersionCode = BuildConfig.VERSION_CODE,
        applicationId = BuildConfig.APPLICATION_ID,
        clientPlatform = RdClientMetadata.PLATFORM,
        clientCapabilities = RdClientMetadata.capabilities,
        googleWebClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID,
        revenueCatPublicKey = BuildConfig.REVENUECAT_PUBLIC_KEY,
        revenueCatOfferingIdentifier = BuildConfig.REVENUECAT_OFFERING_ID,
        firebaseProjectId = BuildConfig.FIREBASE_PROJECT_ID,
    )
}
