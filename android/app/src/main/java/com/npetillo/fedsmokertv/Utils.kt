// Pure helpers shared by the UI, the API client and the unit tests (port of the Roku source/utils.brs).
// No Android, network or Compose in here.
package com.npetillo.fedsmokertv

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.URLEncoder
import java.util.Calendar
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.math.ceil

@Serializable
data class Creds(val server: String, val username: String, val password: String, val ext: String = "m3u8")

/** A live channel. Also the stored favorite shape {id, title, num, icon}. */
@Serializable
data class Channel(val id: String, val title: String, val num: String = "", val icon: String = "")

data class Category(val id: String, val title: String)

data class Programme(val title: String, val desc: String, val start: Long, val ends: Long)

/** Prefilled on the login form; editable for other providers. */
const val DEFAULT_SERVER = "http://ipservz.net"

/** "my.host:8080/" -> "http://my.host:8080" */
fun normalizeServer(input: String): String {
    var s = input.trim()
    if (s.isEmpty()) return ""
    val lower = s.lowercase()
    if (!lower.startsWith("http://") && !lower.startsWith("https://")) s = "http://$s"
    // people often paste a full API or m3u link; keep only scheme://host[:port]
    for (marker in listOf("/player_api.php", "/get.php", "/xmltv.php")) {
        val idx = s.lowercase().indexOf(marker)
        if (idx >= 0) s = s.substring(0, idx)
    }
    s = s.trimEnd('/')
    val sep = s.indexOf("://")
    if (sep < 0 || sep + 3 >= s.length) return "" // scheme only, no host
    return s
}

/** Like BrightScript EncodeUriComponent / JS encodeURIComponent (spaces as %20). */
fun encodeUri(s: String): String =
    URLEncoder.encode(s, "UTF-8").replace("+", "%20").replace("%21", "!").replace("%27", "'")
        .replace("%28", "(").replace("%29", ")").replace("%7E", "~")

fun apiUrl(c: Creds, params: List<Pair<String, Any>> = emptyList()): String {
    val sb = StringBuilder(c.server).append("/player_api.php?username=").append(encodeUri(c.username))
        .append("&password=").append(encodeUri(c.password))
    for ((k, v) in params) sb.append('&').append(k).append('=').append(encodeUri(v.toString()))
    return sb.toString()
}

fun streamUrl(c: Creds, streamId: String, ext: String): String =
    "${c.server}/live/${encodeUri(c.username)}/${encodeUri(c.password)}/$streamId.$ext"

/** JSON value -> string the way Xtream panels mean it (numbers may come as strings or floats). */
fun anyToStr(v: JsonElement?): String {
    if (v == null || v is JsonNull || v !is JsonPrimitive) return ""
    if (v.isString) return v.content
    val c = v.content
    if (c == "true" || c == "false") return c
    val d = c.toDoubleOrNull() ?: return c
    if (d == Math.floor(d) && !d.isInfinite() && kotlin.math.abs(d) < 1e15) return d.toLong().toString()
    return c
}

fun anyToLong(v: JsonElement?): Long {
    val s = anyToStr(v).trim()
    if (s.isEmpty()) return 0
    return s.toLongOrNull() ?: s.toDoubleOrNull()?.toLong() ?: leadingInt(s)
}

private fun leadingInt(s: String): Long {
    // BrightScript ToInt() reads leading digits; keep that behaviour for odd panel values
    val m = Regex("^-?\\d+").find(s) ?: return 0
    return m.value.toLongOrNull() ?: 0
}

@OptIn(ExperimentalEncodingApi::class)
fun decodeB64(v: JsonElement?): String {
    val s = anyToStr(v)
    if (s.isEmpty()) return ""
    return try {
        val out = Base64.Mime.decode(s).toString(Charsets.UTF_8)
        if (out.isEmpty()) s else out
    } catch (e: IllegalArgumentException) {
        s
    }
}

fun nowSecs(): Long = System.currentTimeMillis() / 1000

/** Returns "" when the login response is OK, otherwise a user-facing error. */
fun loginError(json: JsonElement?, now: Long = nowSecs()): String {
    val bad = "Server did not return a valid Xtream response."
    if (json !is JsonObject) return bad
    val ui = json["user_info"] as? JsonObject ?: return bad
    if (anyToLong(ui["auth"]) != 1L) return "Wrong username or password."
    val status = anyToStr(ui["status"])
    if (status.isNotEmpty() && !status.equals("active", ignoreCase = true)) return "Account status: $status"
    val exp = anyToLong(ui["exp_date"])
    if (exp in 1 until now) return "Account expired."
    return ""
}

/** Picks the stream extension from user_info.allowed_output_formats: m3u8 when allowed, else ts. */
fun preferredExt(json: JsonElement?): String {
    val ui = (json as? JsonObject)?.get("user_info") as? JsonObject ?: return "m3u8"
    val formats = ui["allowed_output_formats"] as? JsonArray ?: return "m3u8"
    if (formats.isEmpty()) return "m3u8"
    val names = formats.map { anyToStr(it) }
    if ("m3u8" in names) return "m3u8"
    if ("ts" in names) return "ts"
    return "m3u8"
}

/** get_short_epg -> programmes sorted by start, dropping ended ones. */
fun parseShortEpg(json: JsonElement?, now: Long): List<Programme> {
    val listings = (json as? JsonObject)?.get("epg_listings") as? JsonArray ?: return emptyList()
    val out = ArrayList<Programme>()
    for (e in listings) {
        if (e !is JsonObject) continue
        val start = anyToLong(e["start_timestamp"])
        val ends = anyToLong(e["stop_timestamp"])
        if (start > 0 && ends > now) out.add(Programme(decodeB64(e["title"]), decodeB64(e["description"]), start, ends))
    }
    out.sortBy { it.start }
    return out
}

fun parseCategories(json: JsonElement?): List<Category> =
    (json as? JsonArray)?.mapNotNull { c ->
        if (c !is JsonObject) null else Category(anyToStr(c["category_id"]), anyToStr(c["category_name"]))
    } ?: emptyList()

fun parseStreams(json: JsonElement?): List<Channel> =
    (json as? JsonArray)?.mapNotNull { s ->
        if (s !is JsonObject) null
        else Channel(anyToStr(s["stream_id"]), anyToStr(s["name"]), anyToStr(s["num"]), anyToStr(s["stream_icon"]))
    } ?: emptyList()

fun pad2(n: Int): String = if (n < 10 && n >= 0) "0$n" else n.toString()

private fun cal(secs: Long): Calendar = Calendar.getInstance().apply { timeInMillis = secs * 1000 }

/** Local "HH:MM". */
fun fmtTime(secs: Long): String {
    val c = cal(secs)
    return pad2(c.get(Calendar.HOUR_OF_DAY)) + ":" + pad2(c.get(Calendar.MINUTE))
}

private val WEEKDAYS = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

/** "Thu 20:26" */
fun fmtClock(secs: Long): String = WEEKDAYS[cal(secs).get(Calendar.DAY_OF_WEEK) - 1] + " " + fmtTime(secs)

fun progress(start: Long, ends: Long, now: Long): Float {
    if (ends <= start) return 0f
    return ((now - start).toFloat() / (ends - start)).coerceIn(0f, 1f)
}

/** "Atlas Nature HD" -> "AN" */
fun abbrev(name: String): String =
    name.trim().split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.substring(0, 1).uppercase() }

fun minLeftText(secs: Long): String {
    val mins = ceil(secs / 60.0).toLong().coerceAtLeast(1)
    return "$mins min left"
}

/** Channel-row subtitle: "Coastlines · 34 min left" */
fun nowLine(p: Programme?, now: Long): String = if (p == null) "" else "${p.title} · ${minLeftText(p.ends - now)}"

fun favIndex(favs: List<Channel>, id: String): Int = favs.indexOfFirst { it.id == id }

/** Adds the channel if missing, removes it if present. Returns true when it was added. */
fun favToggle(favs: MutableList<Channel>, entry: Channel): Boolean {
    val idx = favIndex(favs, entry.id)
    if (idx >= 0) {
        favs.removeAt(idx)
        return false
    }
    favs.add(entry)
    return true
}

/** Favorites are stored per account so switching providers doesn't mix lists. */
fun favKey(c: Creds): String {
    val raw = (c.server + "_" + c.username).lowercase().filter { it in 'a'..'z' || it in '0'..'9' }
    return ("favs_$raw").take(64)
}

/**
 * True when the text has characters beyond Latin Extended-A/B (Arabic, Cyrillic, Greek, ...),
 * which ABC Normal can't draw. Dashes, bullet, ellipsis and arrows are fine.
 */
fun hasNonLatin(s: String): Boolean = s.any { ch ->
    val c = ch.code
    c > 0x24F && c != 0x2013 && c != 0x2014 && c != 0x2022 && c != 0x2026 && (c < 0x2190 || c > 0x2193)
}

/** {now, upcoming} relative to the current time. */
data class EpgNow(val now: Programme?, val upcoming: List<Programme>)

fun epgSplit(list: List<Programme>, now: Long): EpgNow {
    var cur: Programme? = null
    val upcoming = ArrayList<Programme>()
    for (p in list) {
        if (p.ends <= now) continue
        if (cur == null && p.start <= now) cur = p else if (p.start > now) upcoming.add(p)
    }
    return EpgNow(cur, upcoming)
}
