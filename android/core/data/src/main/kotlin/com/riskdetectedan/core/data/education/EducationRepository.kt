package com.riskdetectedan.core.data.education

import com.riskdetectedan.core.data.company.PersonnelRepository
import com.riskdetectedan.core.data.company.PersonnelWorkspaceIdentity
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

class EducationFailure(val code: String): Exception(code)
@Singleton class EducationRepository @Inject constructor(private val client: SupabaseClient, private val personnel: PersonnelRepository, private val storage: EducationPrivateStorage) {
    private val mutex = Mutex()
    suspend fun check(identity: PersonnelWorkspaceIdentity) {
        currentCoroutineContext().ensureActive()
        if(personnel.workspaceIdentityNow()!=identity) throw EducationFailure("ACCESS_DENIED")
    }
    private suspend fun rpc(identity: PersonnelWorkspaceIdentity, name: String, args: JsonObject): JsonObject {
        check(identity)
        val result = try {
            val raw = client.postgrest.rpc(name,args).data; require(raw.toByteArray().size<=16777216); Json.parseToJsonElement(raw).jsonObject
        } catch(error: Exception) {
            currentCoroutineContext().ensureActive()
            val response = when(error) { is RestException -> error.response; is ResponseException -> error.response; else -> null }
            val body = response?.let { runCatching { Json.parseToJsonElement(it.bodyAsText()).jsonObject }.getOrNull() }
            if(body?.text("code") in setOf("P0001","28000","22P02","23514","22007","22008")) throw EducationFailure(body!!.text("message"))
            throw EducationFailure("UNAVAILABLE")
        }
        check(identity)
        if(result.text("owner_id")!=identity.ownerID.toString())throw EducationFailure("ACCESS_DENIED")
        return result
    }
    suspend fun context(identity: PersonnelWorkspaceIdentity, id: String? = null) = rpc(identity,"isg_pilot_training_detail_v3",buildJsonObject { put("p_id",id?.let(::JsonPrimitive) ?: JsonNull) })
    suspend fun list(identity: PersonnelWorkspaceIdentity): List<JsonObject> {
        val result = mutableListOf<JsonObject>(); var after: String? = null; val seen = mutableSetOf<String>()
        do {
            val page = rpc(identity,"isg_pilot_training_sessions_v3",buildJsonObject { put("p_after",after?.let(::JsonPrimitive) ?: JsonNull) })
            require(page.number("schema_version")==3); result += page.objects("rows"); after = page.text("next_id").ifEmpty { null }
            if(after!=null)require(seen.add(after))
        } while(after!=null)
        return result
    }
    suspend fun employees(identity: PersonnelWorkspaceIdentity, company: String): List<JsonObject> {
        val result = mutableListOf<JsonObject>(); var after: String? = null; val seen = mutableSetOf<String>()
        do {
            check(identity)
            val page=personnel.read(identity.ownerID.toString(),identity.sessionID.toString(),company,"employees",cursor=after)
            check(identity); result += page.objects("rows"); after=page.text("next").ifEmpty { null }; if(after!=null)require(seen.add(after))
        } while(after!=null)
        return result
    }
    suspend fun preserve(identity: PersonnelWorkspaceIdentity, draft: JsonObject) { check(identity); storage.write("${identity.ownerID}:draft:${draft.text("id")}",draft.toString()) }
    suspend fun draft(identity: PersonnelWorkspaceIdentity,id: String): JsonObject? { check(identity); return storage.read("${identity.ownerID}:draft:$id")?.let { Json.parseToJsonElement(it).jsonObject } }
    suspend fun pending(identity: PersonnelWorkspaceIdentity): JsonObject? { check(identity); return storage.read("${identity.ownerID}:save")?.let { Json.parseToJsonElement(it).jsonObject.getValue("p_payload").jsonObject } }
    suspend fun save(identity: PersonnelWorkspaceIdentity, draft: JsonObject): JsonObject = mutex.withLock {
        check(identity); val key="${identity.ownerID}:save"
        val args = storage.read(key)?.let {
            val prior = Json.parseToJsonElement(it).jsonObject
            if(prior["p_payload"]!=draft)throw EducationFailure("PENDING_OPERATION")
            prior
        } ?: buildJsonObject { put("p_mutation",UUID.randomUUID().toString()); put("p_payload",draft) }.also { storage.write(key,it.toString()) }
        try {
            rpc(identity,"isg_pilot_training_record_v3",args).also {
                require(it["mutation_id"]==args["p_mutation"] && it.number("schema_version")==3)
                storage.remove(key); if(draft.text("action")!="curriculum")storage.remove("${identity.ownerID}:draft:${draft.text("id")}")
            }
        } catch(error: EducationFailure) { if(error.code!="UNAVAILABLE")storage.remove(key); throw error }
    }
    suspend fun certificate(identity: PersonnelWorkspaceIdentity, request: JsonObject, logoPath: String? = null): JsonObject = mutex.withLock {
        check(identity)
        val key="${identity.ownerID}:certificate:${request.text("session_id")}:${request.text("scope_id")}:${request.text("person_id")}"
        val issuing=request.text("action")=="issue"
        var request=request
        if(request.text("action")!="read" && logoPath?.startsWith("${identity.ownerID}/companies/")==true) {
            runCatching {
                val data=client.storage.from("logos").downloadAuthenticated(logoPath)
                require(data.size<=4_194_304)
                val bitmap=android.graphics.BitmapFactory.decodeByteArray(data,0,data.size)
                if(bitmap!=null) {
                    val ratio=minOf(256f/bitmap.width,256f/bitmap.height,1f)
                    val resized=android.graphics.Bitmap.createScaledBitmap(bitmap,maxOf(1,(bitmap.width*ratio).toInt()),maxOf(1,(bitmap.height*ratio).toInt()),true)
                    val bytes=java.io.ByteArrayOutputStream().also { resized.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
                    if(bytes.size<=262144)request=request.with("logo_png_base64",android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP))
                    if(resized!==bitmap)resized.recycle();bitmap.recycle()
                }
            }
            check(identity)
        }
        val payload=if(!issuing)request else storage.read(key)?.let {
            val old=Json.parseToJsonElement(it).jsonObject
            if(old["expected_version"]!=request["expected_version"])throw EducationFailure("VERSION_CONFLICT")
            old
        } ?: request.with("mutation_id",UUID.randomUUID().toString()).also { storage.write(key,it.toString()) }
        try {
            rpc(identity,"isg_pilot_training_certificate_v1",buildJsonObject { put("p_payload",payload) }).also {
                require(it.number("schema_version")==1 && it.getValue("snapshot").jsonObject.text("completion_basis")=="expert_record" && it.getValue("snapshot").jsonObject.number("template_version")==1 && it.getValue("snapshot").jsonObject.number("theme_version")==1)
                if(issuing)storage.remove(key)
            }
        } catch(error: EducationFailure) { if(issuing && error.code!="UNAVAILABLE")storage.remove(key); throw error }
    }
}
