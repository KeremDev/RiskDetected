package com.riskdetectedan.isg.nativecheck

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.lifecycleScope
import com.riskdetectedan.core.data.company.*
import com.riskdetectedan.core.designsystem.isg.*
import com.riskdetectedan.feature.profile.NovaWorkspaceViewModel
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.logging.LogLevel
import io.github.jan.supabase.postgrest.Postgrest
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.UUID

class NativeActivity: ComponentActivity() {
    private var phase by mutableStateOf("connecting")
    private var fixture by mutableStateOf<JsonObject?>(null)
    private var workspace by mutableStateOf<NovaWorkspaceViewModel?>(null)
    private lateinit var client: SupabaseClient
    private lateinit var endpoint: String
    private lateinit var key: String
    private var directoryKind by mutableStateOf<NovaDirectoryKind?>(null)
    private var directoryParent by mutableStateOf<UUID?>(null)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(Build.HARDWARE in setOf("ranchu", "goldfish")) { "Emulator only" }
        endpoint = intent.getStringExtra("url") ?: error("QA endpoint required")
        key = intent.getStringExtra("key") ?: error("QA key required")
        val uri = URI(endpoint)
        check(uri.scheme == "http" && uri.host == "127.0.0.1" && uri.port > 0 && uri.rawPath.isNullOrEmpty() && key.length == 64)
        client = createSupabaseClient(endpoint, key) {
            install(Auth) { logLevel = LogLevel.NONE; alwaysAutoRefresh = false; autoLoadFromStorage = false; autoSaveToStorage = false }
            install(Postgrest)
        }
        setContent { NovaTheme(false) { Content() } }
        lifecycleScope.launch {
            try {
                val f = qa("bootstrap"); check(f["synthetic"]?.jsonPrimitive?.boolean == true)
                fixture = f
                signIn(false)
                workspace = NovaWorkspaceViewModel(PersonnelRepository(client, PersonnelPendingStorage(this@NativeActivity)), CompanyRepository(client)).also { it.start() }
                phase = "ready"
            } catch (_: Exception) { phase = "bootstrap.error" }
        }
    }
    override fun onResume() { super.onResume(); workspace?.refresh() }
    override fun onDestroy() { workspace?.stop(); super.onDestroy() }
    private fun value(key: String) = fixture!!.getValue(key).jsonPrimitive.content
    private suspend fun signIn(second: Boolean) {
        client.auth.signInWith(Email) { email = value(if(second) "secondEmail" else "email"); password = value(if(second) "secondPassword" else "password") }
    }
    suspend fun qa(path: String, action: String? = null): JsonObject = withContext(Dispatchers.IO) {
        val connection = URL("$endpoint/qa/$path").openConnection() as HttpURLConnection
        connection.connectTimeout = 15000; connection.readTimeout = 15000; connection.instanceFollowRedirects = false
        connection.setRequestProperty("apikey", key)
        try {
            if(action != null || path == "finish") {
                connection.requestMethod = "POST"; connection.doOutput = true; connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write((if(action==null) "{}" else buildJsonObject { put("action",action) }.toString()).toByteArray()) }
            }
            check(connection.responseCode == 200)
            Json.parseToJsonElement(connection.inputStream.bufferedReader().use { it.readText() }).jsonObject
        } finally { connection.disconnect() }
    }
    @Composable private fun Content() {
        val model = workspace
        if(model == null) { Text(phase, Modifier.testTag("qa.bootstrap")); return }
        val state by model.state.collectAsState()
        Column(Modifier.fillMaxSize()) {
            Text("$phase|${if(state.resolving) "loading" else "idle"}|${if(state.canWrite) "write" else "readonly"}", Modifier.testTag("qa.state"))
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                for((tag,label) in listOf("a" to "Firma A", "b" to "Firma B")) TextButton({ model.select(UUID.fromString(value(if(tag=="a") "company" else "secondCompany"))) }, Modifier.testTag("qa.company.$tag")) { Text(label) }
                for(tag in listOf("a","b")) TextButton({ phase="working"; lifecycleScope.launch { try { signIn(tag=="b"); phase="account.$tag" } catch (_: Exception) { phase="error" } } }, Modifier.testTag("qa.account.$tag")) { Text("Hesap $tag") }
            }
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                for(action in listOf("drop_next","write_off","read_off","paid_off","reset")) TextButton({
                    phase="working"; lifecycleScope.launch { try { qa("control",action); phase=action; if(action!="drop_next")model.refresh() } catch (_: Exception) { phase="error" } }
                }, Modifier.testTag("qa.$action")) { Text(action) }
            }
            val scope = state.scope
            var menu by remember { mutableStateOf(false) }
            Box {
                TextButton({menu=true},Modifier.testTag("qa.directory")){Text("Rehber")}
                DropdownMenu(menu,{menu=false}) { for(target in NovaDirectoryKind.entries) DropdownMenuItem(text={Text(target.name)},modifier=Modifier.testTag("qa.directory.${target.name}"),onClick={menu=false;open(target)}) }
            }
            if(scope != null) key(scope) {
                val kind=directoryKind
                if(kind!=null) NovaDirectoryDestination(scope,kind,directoryParent,model.directory,state.canWrite){directoryKind=null}
                else NovaPersonnelDestination(scope, "Native QA", model.personnel, directory = model.directory, canWrite = state.canWrite, onBack = { model.select(null) })
            }
            else Text("Firma seçin", Modifier.testTag("qa.no.scope"))
        }
    }
    private fun open(kind: NovaDirectoryKind) {
        val model=workspace?:return;val scope=model.state.value.scope?:return
        lifecycleScope.launch {
            try {
                directoryParent=when(kind) {
                    NovaDirectoryKind.contexts -> model.directory.read(scope,NovaDirectoryKind.workplaces,null,null,false).rows.first{it.title=="Native android workplace"}.id
                    NovaDirectoryKind.assignments,NovaDirectoryKind.employers -> model.personnel.employees(scope,"Native android Son",false,null).rows.first().id
                    else -> null
                }
                directoryKind=kind;phase=kind.name
            }catch(_:Exception){phase="directory.error"}
        }
    }
}
