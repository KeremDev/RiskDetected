package com.riskdetectedan.core.data

import com.riskdetectedan.core.common.RdEnvironmentConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import javax.inject.Singleton
import kotlin.time.Duration.Companion.seconds

@Module
@InstallIn(SingletonComponent::class)
object SupabaseModule {

    @Provides
    @Singleton
    fun provideSupabaseClient(config: RdEnvironmentConfig): SupabaseClient =
        createSupabaseClient(
            supabaseUrl = config.supabaseUrl,
            supabaseKey = config.supabaseAnonKey,
        ) {
            install(Auth)
            install(Postgrest)
            install(Storage)
            install(Functions)
            // Real bug caught via live on-device testing (2026-08-09): supabase-kt's default
            // request timeout is 10s — far too tight for anything that fans out server-side
            // (e.g. the Auth send-email hook chain: GoTrue -> our edge function -> a delivery-
            // claim RPC -> Resend's API -> a completion RPC), and tighter than real device
            // network conditions can need. iOS's SupabaseService.swift deliberately configures a
            // much more generous URLSessionConfiguration on its one shared client
            // (`timeoutIntervalForRequest = 180`, `timeoutIntervalForResource = 600`,
            // `waitsForConnectivity = true`) — Android had no equivalent at all, relying entirely
            // on the library default. Matched via the builder's own public `requestTimeout`
            // (no internal-API opt-in needed, unlike hand-rolling an `HttpTimeout` install via
            // the internal `httpConfig` escape hatch) — `waitsForConnectivity` itself has no
            // direct equivalent exposed here, a long request timeout is the closest real match.
            requestTimeout = 180.seconds
        }
}
