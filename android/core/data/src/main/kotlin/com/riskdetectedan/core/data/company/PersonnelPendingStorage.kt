package com.riskdetectedan.core.data.company

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton

/** Encrypted, non-backup, account-bound pending writes. A corrupt record fails closed. */
@Singleton
class PersonnelPendingStorage @Inject constructor(@ApplicationContext private val context: Context) {
    private val alias = "riskdetected.personnel.pending.v1"
    private fun file(account: String): AtomicFile {
        require(account.matches(Regex("(?:directory:)?[0-9a-f-]{36}:[0-9a-f-]{36}")))
        val directory = File(context.noBackupFilesDir, "isg-personnel-pending")
        check(directory.isDirectory || directory.mkdirs())
        return AtomicFile(File(directory, account.replace(':', '_')))
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    @Synchronized fun read(account: String): String? {
        val file = file(account)
        val data = try { file.openRead().use { input ->
            val bytes = ByteArray(16417); var size = 0
            while (size < bytes.size) { val n = input.read(bytes, size, bytes.size - size); if (n < 0) break; size += n }
            bytes.copyOf(size)
        } } catch (_: java.io.FileNotFoundException) { return null }
        check(data.size in 30..16416 && data[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(1, 13)))
        cipher.updateAAD(account.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(data.copyOfRange(13, data.size)).toString(Charsets.UTF_8)
    }
    @Synchronized fun write(account: String, value: String) {
        val plain = value.toByteArray(Charsets.UTF_8); require(plain.size <= 16384)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(account.toByteArray(Charsets.UTF_8))
        val encrypted = byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
        val file = file(account); val stream = file.startWrite()
        try { stream.write(encrypted); file.finishWrite(stream) } catch (error: Exception) { file.failWrite(stream); throw error }
    }
    @Synchronized fun remove(account: String) {
        val file = file(account); file.delete(); check(!file.baseFile.exists())
    }
}
