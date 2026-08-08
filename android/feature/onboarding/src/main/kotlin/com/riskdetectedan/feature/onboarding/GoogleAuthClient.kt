package com.riskdetectedan.feature.onboarding

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject

/** [email]/[displayName] — read straight off [GoogleIdTokenCredential] (Android's counterpart to
 * `GIDSignInResult.user.profile?.email`/`.name`), passed through to
 * [com.riskdetectedan.core.data.auth.AuthRepository.signInWithGoogleIdToken]'s
 * `emailFallback`/`fullNameFallback` so a real name/email is available even when
 * `auth.users`'s metadata mapping doesn't carry it under the key the profile-bootstrap trigger
 * expects. */
data class GoogleIdTokenResult(
    val idToken: String,
    val rawNonce: String,
    val email: String? = null,
    val displayName: String? = null,
)

/**
 * Credential Manager wrapper — retrieves a Google ID token for [AuthRepository]
 * .signInWithGoogleIdToken. Kept separate from AuthRepository (core:data) since Credential
 * Manager needs an Activity Context, which core:* modules shouldn't depend on.
 */
class GoogleAuthClient @Inject constructor(
    private val config: RdEnvironmentConfig,
) {
    suspend fun requestIdToken(context: Context): RdResult<GoogleIdTokenResult> {
        val rawNonce = UUID.randomUUID().toString()
        val hashedNonce = MessageDigest.getInstance("SHA-256")
            .digest(rawNonce.toByteArray())
            .joinToString("") { "%02x".format(it) }

        val option = GetGoogleIdOption.Builder()
            .setServerClientId(config.googleWebClientId)
            .setNonce(hashedNonce)
            .setFilterByAuthorizedAccounts(false)
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .build()

        return try {
            val response = CredentialManager.create(context)
                .getCredential(context, request)
            val credential = response.credential
            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                val googleIdTokenCredential =
                    GoogleIdTokenCredential.createFrom(credential.data)
                val displayName = googleIdTokenCredential.displayName?.trim()?.ifEmpty { null }
                    ?: listOfNotNull(
                        googleIdTokenCredential.givenName?.trim()?.ifEmpty { null },
                        googleIdTokenCredential.familyName?.trim()?.ifEmpty { null },
                    ).joinToString(" ").trim().ifEmpty { null }
                RdResult.Success(
                    GoogleIdTokenResult(
                        idToken = googleIdTokenCredential.idToken,
                        rawNonce = rawNonce,
                        email = googleIdTokenCredential.id.trim().ifEmpty { null },
                        displayName = displayName,
                    ),
                )
            } else {
                RdResult.Failure(
                    code = "google_credential_unexpected_type",
                    message = "Unexpected credential type from Credential Manager",
                )
            }
        } catch (e: GetCredentialException) {
            RdResult.Failure(
                code = "google_credential_request_failed",
                message = e.message ?: "google_credential_request_failed",
                cause = e,
            )
        } catch (e: GoogleIdTokenParsingException) {
            RdResult.Failure(
                code = "google_id_token_parse_failed",
                message = e.message ?: "google_id_token_parse_failed",
                cause = e,
            )
        }
    }
}
