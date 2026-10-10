// Xtream Codes player_api.php client. All calls are GET and return parsed JSON or a user-facing error.
package com.npetillo.fedsmokertv

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit

const val TAG = "FedSmokerTV"
const val USER_AGENT = "Mozilla/5.0 (Linux; Android TV) FedSmokerTV/" + BuildConfig.VERSION_NAME

sealed class ApiResult<out T> {
    data class Ok<T>(val value: T) : ApiResult<T>()
    /** netError: the server couldn't be reached at all (vs. a bad answer). */
    data class Err(val error: String, val netError: Boolean = false) : ApiResult<Nothing>()
}

class Api {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    val http: OkHttpClient get() = client

    private suspend fun get(url: String, timeoutMs: Long): ApiResult<JsonElement> = withContext(Dispatchers.IO) {
        val call = client.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
            .newCall(Request.Builder().url(url).header("User-Agent", USER_AGENT).build())
        try {
            call.execute().use { resp ->
                when {
                    resp.code == 401 || resp.code == 403 -> ApiResult.Err("Wrong username or password.")
                    !resp.isSuccessful -> ApiResult.Err("Server error (HTTP ${resp.code}).")
                    else -> {
                        val body = resp.body?.string().orEmpty()
                        try {
                            ApiResult.Ok(Json.parseToJsonElement(body))
                        } catch (e: Exception) {
                            ApiResult.Err("Server returned an unexpected response.")
                        }
                    }
                }
            }
        } catch (e: SocketTimeoutException) {
            ApiResult.Err("Server timed out.", netError = true)
        } catch (e: IOException) {
            Log.w(TAG, "GET failed: ${e.message}")
            if (e.message?.contains("timeout", ignoreCase = true) == true) ApiResult.Err("Server timed out.", netError = true)
            else ApiResult.Err("Cannot reach server (${e.message ?: e.javaClass.simpleName}).", netError = true)
        } catch (e: IllegalArgumentException) {
            ApiResult.Err("Invalid server URL.")
        }
    }

    /** On success returns the preferred stream extension. */
    suspend fun login(c: Creds): ApiResult<String> = when (val r = get(apiUrl(c), 20_000)) {
        is ApiResult.Err -> r
        is ApiResult.Ok -> loginError(r.value).let { if (it.isEmpty()) ApiResult.Ok(preferredExt(r.value)) else ApiResult.Err(it) }
    }

    suspend fun categories(c: Creds): ApiResult<List<Category>> =
        when (val r = get(apiUrl(c, listOf("action" to "get_live_categories")), 20_000)) {
            is ApiResult.Err -> r
            is ApiResult.Ok -> ApiResult.Ok(parseCategories(r.value))
        }

    /** catId null = all channels (can be huge, hence the long timeout). */
    suspend fun streams(c: Creds, catId: String?): ApiResult<List<Channel>> {
        val params = mutableListOf<Pair<String, Any>>("action" to "get_live_streams")
        if (catId != null) params.add("category_id" to catId)
        return when (val r = get(apiUrl(c, params), 60_000)) {
            is ApiResult.Err -> r
            is ApiResult.Ok -> withContext(Dispatchers.Default) { ApiResult.Ok(parseStreams(r.value)) }
        }
    }

    suspend fun shortEpg(c: Creds, streamId: String): ApiResult<List<Programme>> =
        when (val r = get(apiUrl(c, listOf("action" to "get_short_epg", "stream_id" to streamId, "limit" to 10)), 20_000)) {
            is ApiResult.Err -> r
            is ApiResult.Ok -> ApiResult.Ok(parseShortEpg(r.value, nowSecs()))
        }
}
