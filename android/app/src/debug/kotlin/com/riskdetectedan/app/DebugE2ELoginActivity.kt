package com.riskdetectedan.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import dagger.hilt.android.AndroidEntryPoint
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import javax.inject.Inject
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Installs an authenticated session for local, on-device E2E runs without adding a password
 * path to the product UI. The caller must first place [CREDENTIALS_FILE] in the debug app's
 * private files directory with `run-as`; the file is consumed exactly once.
 */
@AndroidEntryPoint
class DebugE2ELoginActivity : ComponentActivity() {

    @Inject lateinit var supabaseClient: SupabaseClient

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        lifecycleScope.launch {
            val credentialsFile = File(filesDir, CREDENTIALS_FILE)
            val credentials = runCatching {
                Json.decodeFromString<Credentials>(credentialsFile.readText())
            }.getOrNull()

            // Delete before the network request so neither a crash nor a failed login leaves
            // reusable credentials on the emulator.
            credentialsFile.delete()

            if (credentials != null) {
                runCatching {
                    supabaseClient.auth.signInWith(Email) {
                        email = credentials.email
                        password = credentials.password
                    }
                }
            }

            startActivity(
                Intent(this@DebugE2ELoginActivity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                },
            )
            finish()
        }
    }

    @Serializable
    private data class Credentials(val email: String, val password: String)

    private companion object {
        const val CREDENTIALS_FILE = "debug_e2e_credentials.json"
    }
}
