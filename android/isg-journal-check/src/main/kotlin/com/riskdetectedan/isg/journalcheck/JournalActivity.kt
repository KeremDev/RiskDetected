package com.riskdetectedan.isg.journalcheck

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.widget.TextView
import com.riskdetectedan.core.data.company.PersonnelPendingStorage
import java.io.File

/** No network permission, no production account, no real app UID/key alias access. */
class JournalActivity: Activity() {
    private val account = "11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222"
    private val other = "33333333-3333-4333-8333-333333333333:22222222-2222-4222-8222-222222222222"
    private val body = "{\"operation\":\"qa-same-operation\",\"name\":\"Sentetik Ada\"}"
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!Build.FINGERPRINT.contains("generic") && !Build.MODEL.contains("sdk_gphone")) { finish(); return }
        val result = try { checkJournal(intent.getStringExtra("phase") == "write") } catch (_: Exception) { "FAIL" }
        setContentView(TextView(this).apply { text = result; textSize = 20f; contentDescription = "journal.result" })
    }
    private fun file(key: String) = File(File(noBackupFilesDir,"isg-personnel-pending"),key.replace(':','_'))
    private fun checkJournal(write: Boolean): String {
        val storage = PersonnelPendingStorage(this)
        if (write) {
            storage.remove(account); storage.remove(other); storage.remove("directory:$account")
            check(storage.read(account) == null)
            storage.write(account,body); check(storage.read(account) == body)
            val first = file(account).readBytes()
            check(!first.toString(Charsets.UTF_8).contains("Sentetik Ada"))
            storage.write(account,body); check(!first.contentEquals(file(account).readBytes()))
            check(runCatching { storage.write(account,"x".repeat(16385)) }.isFailure)
            check(storage.read(account) == body && storage.read(other) == null)
            // Ciphertext copied to another account must fail its AAD authentication.
            file(other).writeBytes(file(account).readBytes())
            check(runCatching { storage.read(other) }.isFailure); storage.remove(other)
            storage.write("directory:$account", "directory-pending")
            check(storage.read(account) == body && storage.read("directory:$account") == "directory-pending")
            return "PASS write encryption randomized-iv size-bound aad namespace"
        }
        check(PersonnelPendingStorage(this).read(account) == body)
        check(storage.read("directory:$account") == "directory-pending")
        val original = file(account).readBytes()
        val damaged = original.copyOf(); damaged[damaged.lastIndex] = (damaged.last().toInt() xor 1).toByte()
        file(account).writeBytes(damaged)
        check(runCatching { storage.read(account) }.isFailure)
        file(account).writeBytes(original); check(storage.read(account) == body)
        storage.remove(account); storage.remove("directory:$account")
        check(storage.read(account) == null && storage.read("directory:$account") == null)
        return "PASS restart durable-read tamper-rejected isolated-clear"
    }
}
