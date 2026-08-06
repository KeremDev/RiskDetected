package com.riskdetectedan.core.data.profile

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import javax.inject.Inject
import javax.inject.Singleton

/**
 * `profiles` table access — backend is the single entitlement authority (invariant, master
 * §37): this repository only ever reads what the server already decided (tier, quotas,
 * safety_profile_id, etc.), never derives capability locally.
 */
@Singleton
class ProfileRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetchProfile(userId: String): RdResult<UserProfile> = try {
        val profile = client.postgrest.from("profiles")
            .select(Columns.ALL) {
                filter { eq("id", userId) }
            }
            .decodeSingle<UserProfile>()
        RdResult.Success(profile)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "profile_fetch_failed",
            message = t.message ?: "profile_fetch_failed",
            cause = t,
        )
    }
}
