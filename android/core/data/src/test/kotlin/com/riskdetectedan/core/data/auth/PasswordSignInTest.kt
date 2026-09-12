package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.MemorySessionManager
import io.github.jan.supabase.auth.MemoryCodeVerifierCache
import io.github.jan.supabase.auth.auth
import io.ktor.client.engine.okhttp.OkHttp
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancelAndJoin
import io.github.jan.supabase.auth.FlowType
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.TimeUnit

/** Real pinned Supabase-Kt transport, loopback HTTP only; no credentials, device or live Auth. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PasswordSignInTest {
    private lateinit var server: MockWebServer
    private lateinit var client: SupabaseClient
    @Before fun setup() {
        server = MockWebServer().also { it.start(java.net.InetAddress.getLoopbackAddress(), 0) }
        client = createSupabaseClient(server.url("/").toString(), "synthetic-publishable-key") {
            httpEngine = OkHttp.create()
            install(Auth) {
                logLevel = io.github.jan.supabase.logging.LogLevel.NONE
                flowType = FlowType.PKCE
                scheme = "com.riskdetectedan.app.debug"; host = "login-callback"
                autoLoadFromStorage = false; autoSaveToStorage = false; alwaysAutoRefresh = false
                enableLifecycleCallbacks = false
                sessionManager = MemorySessionManager(); codeVerifierCache = MemoryCodeVerifierCache()
            }
        }
    }
    @After fun cleanup() = runBlocking { client.close(); server.shutdown() }

    @Test fun legacyPasswordAndUnicodeAreSentWithoutTrimmingOrNormalization() = runBlocking {
        // Login must not reject old weak passwords or apply the new signup policy.
        for (password in listOf("old", "  Ab1şifre  ", "Ab1e\u0301🔐  ")) {
            server.enqueue(MockResponse().setResponseCode(400).setBody("""{"error_code":"invalid_credentials","msg":"Invalid login credentials"}"""))
            assertTrue(passwordSignIn(client, "  TEST+tag@Example.invalid  ", password) is RdResult.Failure)
            val request = requireNotNull(server.takeRequest(3, TimeUnit.SECONDS))
            assertEquals("POST", request.method)
            assertEquals("/auth/v1/token", request.requestUrl?.encodedPath)
            assertEquals("password", request.requestUrl?.queryParameter("grant_type"))
            assertEquals("com.riskdetectedan.app.debug://login-callback", request.requestUrl?.queryParameter("redirect_to"))
            val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
            assertEquals("test+tag@example.invalid", body["email"]?.jsonPrimitive?.content)
            assertEquals(password, body["password"]?.jsonPrimitive?.content)
        }
    }

    @Test fun invalidInputsNeverReachTheNetwork() = runBlocking {
        for (email in listOf("", " ", "not-email", "@host", "x@", "x@y@z", "x y@z")) {
            assertEquals("password_email_invalid", (passwordSignIn(client, email, "Some1pass") as RdResult.Failure).code)
        }
        assertEquals("password_required", (passwordSignIn(client, "x@y.invalid", "") as RdResult.Failure).code)
        assertEquals(0, server.requestCount)
    }

    @Test fun serverErrorsDoNotExposeBodyCredentialsOrAccountExistence() = runBlocking {
        for (status in listOf(400, 401, 403, 422, 429, 500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("""{"msg":"private-email@example.invalid raw-password private-token","error_code":"user_not_found"}"""))
            val result = passwordSignIn(client, "x@y.invalid", "Some1pass") as RdResult.Failure
            assertEquals("password_sign_in_failed", result.message)
            assertNull(result.cause)
            requireNotNull(server.takeRequest(3, TimeUnit.SECONDS))
        }
    }

    @Test fun successfulResponseUsesTheSameSdkSessionAndUuid() = runBlocking {
        val id = "11111111-1111-4111-8111-111111111111"
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","token_type":"bearer","expires_in":3600,"user":{"id":"$id","aud":"authenticated","role":"authenticated","email":"x@y.invalid","created_at":"2026-09-13T00:00:00Z","app_metadata":{},"user_metadata":{}}}"""))
        assertEquals(RdResult.Success(Unit), passwordSignIn(client, "x@y.invalid", "Some1pass"))
        assertEquals(id, client.auth.currentUserOrNull()?.id)
        assertEquals("synthetic-refresh", client.auth.currentSessionOrNull()?.refreshToken)
        assertEquals(1, server.requestCount)
    }

    @Test fun signupSubmissionDoesNotClaimANewAccountOrImportASession() = runBlocking {
        // An obfuscated existing-account response must not be interpreted as password creation.
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":"11111111-1111-4111-8111-111111111111","aud":"authenticated","email":"test+tag@example.invalid","created_at":"2026-09-13T00:00:00Z","identities":[],"app_metadata":{},"user_metadata":{}}"""))
        assertEquals(RdResult.Success(Unit), passwordSignUp(client, " TEST+tag@Example.invalid ", " Ab1şifreİ ", RdAppLanguage.Turkish))
        val request = requireNotNull(server.takeRequest(3, TimeUnit.SECONDS))
        assertEquals("/auth/v1/signup", request.requestUrl?.encodedPath)
        assertEquals("com.riskdetectedan.app.debug://login-callback", request.requestUrl?.queryParameter("redirect_to"))
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals(" Ab1şifreİ ", body["password"]?.jsonPrimitive?.content)
        assertEquals("tr-TR", body["data"]?.jsonObject?.get("content_locale")?.jsonPrimitive?.content)
        assertTrue(body.getValue("code_challenge").jsonPrimitive.content.isNotBlank())
        assertNull(client.auth.currentSessionOrNull())
    }

    @Test fun signupPolicyRejectsInvalidPasswordWithoutNetwork() = runBlocking {
        for (value in listOf("", "abcdefgh1", "Ab1🔐🔐", "Aa1" + "x".repeat(70))) {
            assertEquals("password_policy_invalid", (passwordSignUp(client, "x@y.invalid", value, RdAppLanguage.English) as RdResult.Failure).code)
        }
        assertEquals(0, server.requestCount)
    }

    @Test fun recoveryUsesExistingCallbackAndPkceWithoutCreatingASession() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        assertEquals(RdResult.Success(Unit), passwordRecoveryRequest(client, " TEST+tag@Example.invalid "))
        val request = requireNotNull(server.takeRequest(3, TimeUnit.SECONDS))
        assertEquals("/auth/v1/recover", request.requestUrl?.encodedPath)
        assertEquals("com.riskdetectedan.app.debug://login-callback", request.requestUrl?.queryParameter("redirect_to"))
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals("test+tag@example.invalid", body["email"]?.jsonPrimitive?.content)
        assertTrue(body.getValue("code_challenge").jsonPrimitive.content.isNotBlank())
        assertNull(client.auth.currentSessionOrNull())
    }

    @Test fun enrollmentErrorsDoNotExposeServerBodyOrAccountExistence() = runBlocking {
        for (status in listOf(400, 401, 403, 422, 429, 500)) {
            for (signup in listOf(true, false)) {
                server.enqueue(MockResponse().setResponseCode(status).setBody("""{"msg":"private-email@example.invalid raw-password private-token","error_code":"user_not_found"}"""))
                val result = (if (signup) passwordSignUp(client, "x@y.invalid", "Some1pass", RdAppLanguage.English)
                    else passwordRecoveryRequest(client, "x@y.invalid")) as RdResult.Failure
                val code = if (signup) "password_signup_failed" else "password_recovery_failed"
                assertEquals(code, result.code)
                assertEquals(code, result.message)
                assertNull(result.cause)
                requireNotNull(server.takeRequest(3, TimeUnit.SECONDS))
            }
        }
    }

    @Test fun signupWhileSignedInDoesNotCreateOrReplaceAnAccount() = runBlocking {
        successfulResponseUsesTheSameSdkSessionAndUuid()
        assertEquals("password_signup_requires_signed_out", (passwordSignUp(client, "other@y.invalid", "Some1pass", RdAppLanguage.English) as RdResult.Failure).code)
        assertEquals("11111111-1111-4111-8111-111111111111", client.auth.currentUserOrNull()?.id)
        assertEquals(1, server.requestCount)
    }

    @Test fun unexpectedAutoconfirmIsAnErrorButSdkSessionImportIsDocumented() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","token_type":"bearer","expires_in":3600,"user":{"id":"11111111-1111-4111-8111-111111111111","aud":"authenticated","role":"authenticated","email":"x@y.invalid","created_at":"2026-09-13T00:00:00Z","app_metadata":{},"user_metadata":{}}}"""))
        assertEquals("password_confirmation_required", (passwordSignUp(client, "x@y.invalid", "Some1pass", RdAppLanguage.English) as RdResult.Failure).code)
        // A returned failure cannot undo an SDK auth-state event. Activation requires
        // confirmed server configuration AND an account-scoped purpose coordinator.
        assertNotNull(client.auth.currentSessionOrNull())
        assertEquals(1, server.requestCount)
    }

    @Test fun cancellationIsNotConvertedIntoAnAuthenticationFailure() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.NO_RESPONSE))
        val cancelled = java.util.concurrent.atomic.AtomicBoolean(false)
        val job = launch(Dispatchers.Default) {
            try { passwordSignIn(client, "x@y.invalid", "Some1pass"); fail("Request should be cancelled") }
            catch (_: CancellationException) { cancelled.set(true) }
        }
        assertNotNull(server.takeRequest(3, TimeUnit.SECONDS))
        job.cancelAndJoin()
        assertTrue(cancelled.get())
    }
}
