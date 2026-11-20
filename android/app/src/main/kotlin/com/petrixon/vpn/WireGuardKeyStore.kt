package com.petrixon.vpn

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.wireguard.crypto.Key
import com.wireguard.crypto.KeyPair

class WireGuardKeyStore(context: Context) {
    private val prefs: SharedPreferences

    init {
        val masterKey = MasterKey.Builder(context.applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        prefs = EncryptedSharedPreferences.create(
            context.applicationContext,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    /** Returns the device WireGuard public key (base64). Private key never leaves native prefs. */
    fun getOrCreatePublicKey(): String {
        val existing = prefs.getString(KEY_PRIVATE, null)
        val keyPair = if (existing.isNullOrEmpty()) {
            val generated = KeyPair()
            prefs.edit().putString(KEY_PRIVATE, generated.privateKey.toBase64()).apply()
            generated
        } else {
            KeyPair(Key.fromBase64(existing))
        }
        return keyPair.publicKey.toBase64()
    }

    fun loadPrivateKey(): Key {
        val existing = prefs.getString(KEY_PRIVATE, null)
            ?: throw IllegalStateException("WireGuard private key missing — call getOrCreatePublicKey first")
        return Key.fromBase64(existing)
    }

    companion object {
        private const val PREFS_NAME = "petrikvpn_wireguard_keys"
        private const val KEY_PRIVATE = "private_key"
    }
}
