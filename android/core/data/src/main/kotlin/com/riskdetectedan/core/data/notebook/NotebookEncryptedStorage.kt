package com.riskdetectedan.core.data.notebook

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotebookEncryptedStorage @Inject constructor(@ApplicationContext private val context: Context) : NotebookStorage {
    private val alias = "riskdetected.notebook.outbox.v1"
    private fun file(owner: UUID): AtomicFile {
        val directory = File(context.noBackupFilesDir, "isg-notebook-outbox")
        check(directory.isDirectory || directory.mkdirs())
        return AtomicFile(File(directory, owner.toString()))
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
    @Synchronized override fun read(owner: UUID): String? {
        val data = try { file(owner).openRead().use { input ->
            val bytes = ByteArray(2_000_030); var size = 0
            while (size < bytes.size) { val n = input.read(bytes, size, bytes.size - size); if (n < 0) break; size += n }
            bytes.copyOf(size)
        } }
            catch (_: java.io.FileNotFoundException) { return null }
        check(data.size in 30..2_000_029 && data[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(1, 13)))
        cipher.updateAAD(owner.toString().toByteArray(Charsets.UTF_8))
        return cipher.doFinal(data.copyOfRange(13, data.size)).toString(Charsets.UTF_8)
    }
    @Synchronized override fun write(owner: UUID, value: String) {
        val plain = value.toByteArray(Charsets.UTF_8); require(plain.size <= 2_000_000)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(owner.toString().toByteArray(Charsets.UTF_8))
        val file = file(owner); val stream = file.startWrite()
        try { stream.write(byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
}
