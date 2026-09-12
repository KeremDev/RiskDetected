package com.riskdetectedan.core.data.company

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.ktor.client.engine.okhttp.OkHttp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Actual SDK GET/cancellation only. Synthetic loopback server, no live RLS or Auth claims. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class CompanyListTransportTest {
    private lateinit var server: MockWebServer
    private lateinit var client: SupabaseClient
    private lateinit var repository: CompanyRepository

    @Before fun setup() {
        server = MockWebServer().also { it.start(InetAddress.getLoopbackAddress(), 0) }
        client = createSupabaseClient(server.url("/").toString(), "synthetic-publishable-key") {
            httpEngine = OkHttp.create()
            install(Postgrest)
        }
        repository = CompanyRepository(client)
    }

    @After fun cleanup() = runBlocking { client.close(); server.shutdown() }

    @Test fun activeAndArchivedQueriesKeepExistingContract() = runBlocking {
        for (archived in listOf(false, true)) {
            server.enqueue(MockResponse().setBody("""[{"id":"11111111-1111-4111-8111-111111111111","user_id":"22222222-2222-4222-8222-222222222222","name":"Sentetik Firma","hazard_class":"high","is_archived":$archived}]"""))
            val rows = (repository.listCompanies(archived) as RdResult.Success).value
            assertEquals(1, rows.size)
            assertEquals("Sentetik Firma", rows.single().name)
            assertEquals(archived, rows.single().isArchived)
            val request = requireNotNull(server.takeRequest(3, TimeUnit.SECONDS))
            assertEquals("GET", request.method)
            assertEquals("/rest/v1/companies", request.requestUrl?.encodedPath)
            assertEquals(if (archived) null else "eq.false", request.requestUrl?.queryParameter("is_archived"))
            assertEquals("created_at.desc.nullslast", request.requestUrl?.queryParameter("order"))
        }
    }

    @Test fun cancelledListNeverReturnsSuccessOrDisplayableFailure() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val cancelled = AtomicBoolean(false)
        val returned = AtomicBoolean(false)
        val job = launch(Dispatchers.Default) {
            try { repository.listCompanies(); returned.set(true) }
            catch (_: CancellationException) { cancelled.set(true) }
        }
        assertNotNull(server.takeRequest(3, TimeUnit.SECONDS))
        job.cancelAndJoin()
        assertTrue(cancelled.get())
        assertFalse(returned.get())
    }
}
