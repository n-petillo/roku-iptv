// Port of the Roku source/tests.brs cases, plus a few Android-only ones at the end.
package com.npetillo.fedsmokertv

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class UtilsTest {
    private fun j(s: String): JsonElement = Json.parseToJsonElement(s)

    @Test fun normalizeServer() {
        assertEquals("http://my.host:8080", normalizeServer("my.host:8080"))
        assertEquals("http://a.b:80", normalizeServer(" http://a.b:80/ "))
        assertEquals("https://a.b", normalizeServer("https://a.b"))
        assertEquals("http://a.b:8080", normalizeServer("http://a.b:8080/player_api.php?username=x"))
        assertEquals("http://a.b", normalizeServer("a.b/get.php?username=x&type=m3u"))
        assertEquals("http://ipservz.net", normalizeServer(DEFAULT_SERVER))
        assertEquals("", normalizeServer("  "))
        assertEquals("", normalizeServer("http://"))
        assertEquals("", normalizeServer("http:///"))
    }

    @Test fun preferredExt() {
        assertEquals("m3u8", preferredExt(j("""{"user_info":{}}""")))
        assertEquals("ts", preferredExt(j("""{"user_info":{"allowed_output_formats":["ts"]}}""")))
        assertEquals("m3u8", preferredExt(j("""{"user_info":{"allowed_output_formats":["ts","m3u8","rtmp"]}}""")))
        assertEquals("m3u8", preferredExt(null))
    }

    private val creds = Creds("http://h:1", "u s", "p&w")

    @Test fun urls() {
        assertEquals(
            "http://h:1/player_api.php?username=u%20s&password=p%26w&action=get_live_streams&category_id=5",
            apiUrl(creds, listOf("action" to "get_live_streams", "category_id" to 5)),
        )
        assertEquals("http://h:1/player_api.php?username=u%20s&password=p%26w", apiUrl(creds))
        assertEquals("http://h:1/live/u%20s/p%26w/42.m3u8", streamUrl(creds, "42", "m3u8"))
    }

    @Test fun anyTo() {
        assertEquals("12", anyToStr(JsonPrimitive(12)))
        assertEquals("12", anyToStr(JsonPrimitive(12.0)))
        assertEquals("", anyToStr(JsonNull))
        assertEquals(1700000000L, anyToLong(JsonPrimitive("1700000000")))
        assertEquals("Hello World", decodeB64(JsonPrimitive("SGVsbG8gV29ybGQ=")))
        assertEquals("", decodeB64(null))
    }

    @Test fun loginError() {
        assertEquals("", loginError(j("""{"user_info":{"auth":1,"status":"Active","exp_date":null}}""")))
        assertEquals("", loginError(j("""{"user_info":{"auth":"1","status":"Active","exp_date":"4102444800"}}""")))
        assertEquals("Wrong username or password.", loginError(j("""{"user_info":{"auth":0}}""")))
        assertEquals("Account expired.", loginError(j("""{"user_info":{"auth":1,"status":"Active","exp_date":"1000"}}""")))
        assertEquals("Account status: Disabled", loginError(j("""{"user_info":{"auth":1,"status":"Disabled"}}""")))
        assertEquals("Server did not return a valid Xtream response.", loginError(null))
    }

    @Test fun shortEpg() {
        val json = j(
            """{"epg_listings":[
              {"title":"QiBTaG93","description":"","start_timestamp":"2000","stop_timestamp":"3000"},
              {"title":"T2xk","description":"","start_timestamp":"500","stop_timestamp":"900"},
              {"title":"QSBTaG93","description":"RGVzYw==","start_timestamp":"1000","stop_timestamp":"2000"}
            ]}""",
        )
        val epg = parseShortEpg(json, 1500)
        assertEquals(2, epg.size)
        assertEquals("A Show", epg[0].title)
        assertEquals("Desc", epg[0].desc)
        assertEquals("B Show", epg[1].title)
        assertEquals(0, parseShortEpg(null, 0).size)
        assertEquals(0, parseShortEpg(j("""{"epg_listings":null}"""), 0).size)
    }

    @Test fun timeAndProgress() {
        assertEquals(0.5f, progress(1000, 2000, 1500))
        assertEquals(0f, progress(1000, 2000, 0))
        assertEquals(1f, progress(1000, 2000, 9999))
        assertEquals("07", pad2(7))
        assertEquals(5, fmtTime(1700000000).length)
        assertEquals(9, fmtClock(1700000000).length)
    }

    @Test fun text() {
        assertEquals("AN", abbrev("Atlas Nature HD"))
        assertEquals("B", abbrev(" bbc "))
        assertEquals("", abbrev(""))
        assertEquals("34 min left", minLeftText(34 * 60))
        assertEquals("2 min left", minLeftText(61))
        assertEquals("1 min left", minLeftText(0))
        assertEquals("Coastlines · 34 min left", nowLine(Programme("Coastlines", "", 0, 3000), 3000L - 34 * 60))
        assertEquals("", nowLine(null, 0))
    }

    @Test fun favorites() {
        val favs = mutableListOf<Channel>()
        assertEquals(true, favToggle(favs, Channel("1", "A")))
        assertEquals(true, favToggle(favs, Channel("2", "B")))
        assertEquals(1, favIndex(favs, "2"))
        assertEquals(false, favToggle(favs, Channel("1", "A")))
        assertEquals(1, favs.size)
        assertEquals(-1, favIndex(favs, "1"))
    }

    @Test fun nonLatin() {
        assertEquals(false, hasNonLatin("Atlas Nature HD · 34 min left – é…"))
        assertEquals(true, hasNonLatin("قناة"))
        assertEquals(true, hasNonLatin("Первый канал"))
        assertEquals(false, hasNonLatin("← →"))
    }

    // ---- Android-only ----

    @Test fun parsers() {
        val cats = parseCategories(j("""[{"category_id":"7","category_name":"News"},{"category_id":8,"category_name":"Sport"},"junk"]"""))
        assertEquals(listOf(Category("7", "News"), Category("8", "Sport")), cats)
        val chans = parseStreams(j("""[{"stream_id":42,"name":"BBC One","stream_icon":"http://x/l.png","num":101}]"""))
        assertEquals(listOf(Channel("42", "BBC One", "101", "http://x/l.png")), chans)
        assertEquals(0, parseStreams(j("""{"error":"nope"}""")).size)
    }

    @Test fun favKeyAndSplit() {
        assertEquals("favs_httpipservznetbob", favKey(Creds("http://ipservz.net", "Bob", "x")))
        val list = listOf(Programme("A", "", 1000, 2000), Programme("B", "", 2000, 3000), Programme("C", "", 3000, 4000))
        val s = epgSplit(list, 1500)
        assertEquals("A", s.now?.title)
        assertEquals(listOf("B", "C"), s.upcoming.map { it.title })
        assertEquals(null, epgSplit(list, 500).now)
        assertEquals("utf8 ✓", decodeB64(JsonPrimitive("dXRmOCDinJM=")))
        assertEquals("not base64!", decodeB64(JsonPrimitive("not base64!")))
    }
}
