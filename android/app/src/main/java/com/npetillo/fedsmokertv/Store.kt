// Credentials and per-account favorites, saved on the device with DataStore.
package com.npetillo.fedsmokertv

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val Context.dataStore by preferencesDataStore("iptv")

class Store(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val credsKey = stringPreferencesKey("creds")

    // The file is tiny; reading it synchronously at launch keeps start-up logic simple.
    private fun read(key: String): String? =
        runBlocking { context.dataStore.data.first()[stringPreferencesKey(key)] }

    private suspend fun write(key: String, value: String) {
        context.dataStore.edit { it[stringPreferencesKey(key)] = value }
    }

    fun loadCreds(): Creds? = read(credsKey.name)?.let {
        try { json.decodeFromString<Creds>(it) } catch (e: Exception) { null }
    }

    suspend fun saveCreds(c: Creds) = write(credsKey.name, json.encodeToString(c))

    fun loadFavs(c: Creds): List<Channel> = read(favKey(c))?.let {
        try { json.decodeFromString<List<Channel>>(it) } catch (e: Exception) { null }
    } ?: emptyList()

    suspend fun saveFavs(c: Creds, favs: List<Channel>) = write(favKey(c), json.encodeToString(favs))
}
