// Live TV drawing: favorites home, 3 panels, player (preview or fullscreen), banner, toast, dialogs.
// Pure rendering of LiveState; keys are handled in LiveState.onKey.
package com.npetillo.fedsmokertv.ui

import android.graphics.Color as AColor
import androidx.annotation.OptIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.npetillo.fedsmokertv.Category
import com.npetillo.fedsmokertv.Channel
import com.npetillo.fedsmokertv.FAV
import com.npetillo.fedsmokertv.LiveState
import com.npetillo.fedsmokertv.Mode
import com.npetillo.fedsmokertv.PlayStatus
import com.npetillo.fedsmokertv.R
import com.npetillo.fedsmokertv.abbrev
import com.npetillo.fedsmokertv.fmtClock
import com.npetillo.fedsmokertv.fmtTime
import com.npetillo.fedsmokertv.minLeftText
import com.npetillo.fedsmokertv.progress

private fun channelLabel(ch: Channel) = if (ch.num.isNotEmpty()) "${ch.num} · ${ch.title}" else ch.title

/** Keeps the focused row inside a window of `rows` visible rows (focus floats, the list scrolls at the edges). */
private suspend fun LazyListState.keepVisible(idx: Int, rows: Int) {
    val first = firstVisibleItemIndex
    if (idx < first) scrollToItem(idx) else if (idx > first + rows - 1) scrollToItem(idx - rows + 1)
}

@Composable
fun LiveScreen(s: LiveState) {
    // hoisted so scroll positions survive fullscreen and back
    val catList = rememberLazyListState()
    val chanList = rememberLazyListState()
    Box(Modifier.box(1920, 1080)) {
        if (s.mode != Mode.Full) Header(s)
        when (s.mode) {
            Mode.Home -> Home(s)
            Mode.Panels -> Panels(s, catList, chanList)
            Mode.Full -> {}
        }
        if (s.mode != Mode.Home) PlayerArea(s)
        if (s.mode == Mode.Full && s.banner) Banner(s)
        if (s.mode != Mode.Full) Footer(hints(s))
        s.toast?.let { Toast(it, s.toastOk) }
        s.dialog?.let { d ->
            Box(Modifier.fillMaxSize().background(P.ink85)) {
                Column(Modifier.align(Alignment.Center).width(860.dp).rounded(P.ink, 12).outline(P.w15, 12).padding(56.dp)) {
                    Txt(d.title, 44, P.w100)
                    if (d.message.isNotEmpty()) {
                        Spacer(Modifier.height(16.dp))
                        Txt(d.message, 24, P.w60, maxLines = 2)
                    }
                    Spacer(Modifier.height(40.dp))
                    Row {
                        d.buttons.forEachIndexed { i, b ->
                            if (i > 0) Spacer(Modifier.width(20.dp))
                            PillButton(b, i == d.idx)
                        }
                    }
                }
            }
        }
    }
}

private fun hints(s: LiveState): List<Pair<String, String>> {
    val back = if (s.favs.isNotEmpty()) "Favorites" else "Exit"
    return when {
        s.mode == Mode.Home && s.homeOnTabs -> listOf("← →" to "Choose", "OK" to "Open", "Back" to "Exit · refresh · log out")
        s.mode == Mode.Home -> listOf("← → ↑ ↓" to "Move", "OK" to "Watch fullscreen", "Hold OK" to "Remove favorite", "Back" to "Exit · refresh · log out")
        s.chansFocused -> {
            val ch = s.focusedChannel()
            val ok = if (ch != null && s.failed && s.playing?.id == ch.id) "Try again" else "Play · again for fullscreen"
            val fav = if (ch != null && s.isFav(ch.id)) "Remove favorite" else "Favorite"
            listOf("← →" to "Switch panel", "OK" to ok, "Hold OK" to fav, "Back" to back)
        }
        else -> listOf("← →" to "Switch panel", "OK" to "Open", "Back" to back)
    }
}

// ---------- header ----------

@Composable
private fun Header(s: LiveState) {
    Row(Modifier.at(96, 40).height(64.dp), verticalAlignment = Alignment.CenterVertically) {
        Txt("FedSmokerTV", 34, P.w100)
        if (s.mode == Mode.Panels) {
            Spacer(Modifier.width(28.dp))
            Txt("LIVE TV", 20, P.w35, Modifier.padding(top = 6.dp))
        } else {
            Spacer(Modifier.width(38.dp))
            listOf("FAVORITES", "ALL CHANNELS", "CATEGORIES").forEachIndexed { i, name ->
                val focused = s.homeOnTabs && s.tabIdx == i
                val current = i == 0
                var m = Modifier.height(44.dp)
                if (focused) m = m.rounded(P.w100, 22)
                if (current && !focused) m = m.drawBehind {
                    val pad = 18.dp.toPx()
                    drawRect(Color.White, Offset(pad, size.height - 2.dp.toPx()), Size(size.width - 2 * pad, 2.dp.toPx()))
                }
                Box(m.padding(horizontal = 18.dp), contentAlignment = Alignment.Center) {
                    Txt(name, 20, if (focused) P.ink else if (current) P.w100 else P.w60)
                }
                Spacer(Modifier.width(4.dp))
            }
        }
    }
    Txt(fmtClock(s.now), 30, P.w60, Modifier.at(1424, 52).width(400.dp), align = TextAlign.End)
    if (s.mode == Mode.Panels) Box(Modifier.at(96, 136).box(1728, 1).background(P.w10))
}

// ---------- shared bits ----------

/** Channel logo with initials until (or instead of) the image. */
@Composable
private fun Logo(url: String, title: String, w: Int, h: Int, logoW: Int, logoH: Int, abbrSize: Int, abbrColor: Color) {
    var ok by remember(url) { mutableStateOf(false) }
    Box(Modifier.box(w, h), contentAlignment = Alignment.Center) {
        if (!ok) Txt(abbrev(title), abbrSize, abbrColor)
        if (url.isNotEmpty()) {
            AsyncImage(
                model = url, contentDescription = null, modifier = Modifier.box(logoW, logoH),
                onSuccess = { ok = true }, onError = { ok = false },
            )
        }
    }
}

@Composable
private fun Star(color: Color, modifier: Modifier = Modifier) {
    Image(painterResource(R.drawable.star), null, modifier.box(26, 26), colorFilter = ColorFilter.tint(color))
}

/** ok = false: failure, no check mark. */
@Composable
private fun Toast(text: String, ok: Boolean) {
    Box(Modifier.box(1920, 1080)) {
        Row(
            Modifier.align(Alignment.TopEnd).offset(x = (-96).dp, y = 160.dp).height(64.dp).rounded(P.w12, 12).padding(start = 24.dp, end = 28.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (ok) {
                Image(painterResource(R.drawable.check), null, Modifier.box(24, 24), colorFilter = ColorFilter.tint(P.w100))
                Spacer(Modifier.width(16.dp))
            }
            Txt(text, 24, P.w100, Modifier.widthIn(max = 900.dp))
        }
    }
}

// ---------- home: favorites grid ----------

@Composable
private fun Home(s: LiveState) {
    val n = s.favs.size
    Row(Modifier.at(96, 166), verticalAlignment = Alignment.Bottom) {
        Txt("Favorites", 64, P.w100)
        Spacer(Modifier.width(24.dp))
        Txt(n.toString(), 64, P.w35, medium = true)
    }
    val first = maxOf(0, s.gridIdx / 4 - 1) // two rows visible; scroll to keep the focused row on screen
    for (r in first..first + 1) for (c in 0..3) {
        val i = r * 4 + c
        if (i < n) FavTile(s, s.favs[i], i == s.gridIdx && !s.homeOnTabs, Modifier.at(96 + c * 440, 310 + (r - first) * 324))
    }
}

@Composable
private fun FavTile(s: LiveState, ch: Channel, active: Boolean, modifier: Modifier) {
    Box(modifier.box(408, 276)) {
        if (active) Box(Modifier.at(-7, -7).box(422, 214).outline(P.w100, 12, 3))
        Box(Modifier.box(408, 200).rounded(P.w06, 8).outline(P.w10, 8)) {
            Logo(ch.icon, ch.title, 408, 200, 200, 110, 28, P.w35)
        }
        val cur = s.epgNow(ch.id)?.now
        val prog = if (cur != null) progress(cur.start, cur.ends, s.now) else 0f
        if (prog > 0f) {
            Box(Modifier.at(0, 196).box(408, 4).background(P.ink50))
            Box(Modifier.at(0, 196).box((408 * prog).toInt(), 4).background(if (active) P.w100 else P.w85))
        }
        Row(Modifier.at(0, 214).width(408.dp)) {
            if (ch.num.isNotEmpty()) {
                Txt(ch.num, 24, if (active) P.w60 else P.w35)
                Spacer(Modifier.width(14.dp))
            }
            Txt(ch.title, 24, if (active) P.w100 else P.w85)
        }
        Txt(s.nowText(ch.id), 20, if (active) P.w60 else P.w35, Modifier.at(0, 252).width(408.dp))
    }
}

// ---------- panels ----------

private val CAT_SKEL = listOf(220, 160, 120, 180, 140, 200, 110, 150, 230, 170)
private val CHAN_SKEL = listOf(260, 200, 310, 240, 280, 190, 300, 220)

@Composable
private fun Panels(s: LiveState, catList: LazyListState, chanList: LazyListState) {
    // categories
    Txt("CATEGORIES", 20, P.w35, Modifier.at(96, 172))
    val cats = s.cats
    if (cats == null) {
        CAT_SKEL.forEachIndexed { i, w -> Box(Modifier.at(96, 214 + i * 62 + 20).box(w, 22).rounded(P.w08, 4)) }
    } else {
        LaunchedEffect(s.catIdx) { catList.keepVisible(s.catIdx, 12) }
        LazyColumn(Modifier.at(76, 214).box(380, 744), state = catList, userScrollEnabled = false) {
            itemsIndexed(cats) { i, c ->
                CategoryRow(c, s.catCount(c.id), i == s.catIdx, i == s.catIdx && !s.chansFocused)
            }
        }
    }
    Box(Modifier.at(476, 160).box(1, 830).background(P.w10))

    // channels
    val chans = s.shownChans
    val catTitle = cats?.firstOrNull { it.id == s.curCatId }?.title
    val title = when {
        chans == null || catTitle == null -> "LOADING CHANNELS…"
        else -> catTitle.uppercase() + " · " + if (chans.size == 1) "1 CHANNEL" else "${chans.size} CHANNELS"
    }
    Txt(title, 20, P.w35, Modifier.at(516, 172).width(620.dp))
    if (chans == null) {
        CHAN_SKEL.forEachIndexed { i, w ->
            val y = 214 + i * 92
            Box(Modifier.at(536, y + 34).box(60, 20).rounded(P.w06, 4))
            Box(Modifier.at(618, y + 17).box(72, 54).rounded(P.w06, 4))
            Box(Modifier.at(712, y + 22).box(w, 22).rounded(P.w08, 4))
            Box(Modifier.at(712, y + 56).box(180, 16).rounded(P.w05, 4))
        }
    } else {
        LaunchedEffect(s.chanIdx, s.curCatId) { chanList.keepVisible(s.chanIdx, 8) }
        LazyColumn(
            Modifier.at(516, 214).box(620, 736), state = chanList, userScrollEnabled = false,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // no item keys: providers sometimes repeat a stream id, and duplicate keys crash LazyColumn
            itemsIndexed(chans) { i, c ->
                ChannelRow(s, c, i == s.chanIdx, i == s.chanIdx && s.chansFocused)
            }
        }
        val msg = when {
            s.chansError.isNotEmpty() -> s.chansError
            chans.isEmpty() && s.curCatId == FAV -> "No favorites yet."
            chans.isEmpty() -> "No channels in this category."
            else -> ""
        }
        if (msg.isNotEmpty()) Txt(msg, 24, P.w60, Modifier.at(536, 520).width(580.dp), maxLines = 3, align = TextAlign.Center)
        // hint under a short favorites list
        if (s.curCatId == FAV && chans.size < 8) {
            val y = if (chans.isEmpty()) 580 else 214 + chans.size * 92 + 28
            Row(Modifier.at(536, y), verticalAlignment = Alignment.CenterVertically) {
                Txt("Hold", 20, P.w35)
                Spacer(Modifier.width(10.dp))
                Box(Modifier.height(28.dp).outline(P.w35, 6).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) { Txt("OK", 16, P.w60) }
                Spacer(Modifier.width(10.dp))
                Txt("on any channel to add or remove it.", 20, P.w35)
            }
        }
    }
    Box(Modifier.at(1176, 160).box(1, 830).background(P.w10))

    // preview frame (the player sits on top) + programme info for the focused channel
    Box(Modifier.at(1216, 172).box(608, 342).rounded(Color.Black, 8))
    Info(s, if (chans == null) null else s.focusedChannel())
}

@Composable
private fun CategoryRow(c: Category, count: Int?, selected: Boolean, active: Boolean) {
    val isFav = c.id == FAV
    val (bar, name, cnt, star) = when {
        active -> listOf(P.w100, P.w100, P.w60, P.w100)
        selected -> listOf(P.w35, P.w85, P.w35, P.w85)
        else -> listOf(P.w35, P.w60, P.w35, P.w60)
    }
    Box(Modifier.box(380, 62)) {
        if (selected) Box(Modifier.box(3, 62).background(bar))
        Box(Modifier.at(20, 0).box(340, 62)) {
            var x = if (selected) 20 else 0
            if (isFav) {
                Star(star, Modifier.at(x, 18))
                x += 40
            }
            RowTxt(c.title, 28, name, 62, Modifier.at(x, 0).width((240 - x).dp))
            RowTxt(count?.toString() ?: "", 22, cnt, 62, Modifier.at(240, 0).width(100.dp), align = TextAlign.End)
            if (isFav) Box(Modifier.at(0, 61).box(340, 1).background(P.w10))
        }
    }
}

@Composable
private fun ChannelRow(s: LiveState, c: Channel, selected: Boolean, active: Boolean) {
    val isPlaying = s.playing?.id == c.id && !s.failed
    val isFav = s.isFav(c.id)
    val fg = if (active) P.ink else P.w85
    val dim = if (active) P.ink60 else P.w35
    Box(Modifier.box(620, 88).let { if (selected) it.rounded(if (active) P.w100 else P.w06, 8) else it }) {
        RowTxt(c.num, 24, dim, 88, Modifier.at(20, 0).width(60.dp))
        Box(Modifier.at(102, 17).box(72, 54).rounded(if (active) P.ink08 else P.w08, 4)) {
            Logo(c.icon, c.title, 72, 54, 64, 48, 18, if (active) P.ink60 else P.w60)
        }
        Row(Modifier.fillMaxSize().padding(start = 196.dp, end = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Txt(c.title, 28, fg)
                Spacer(Modifier.height(6.dp))
                Txt(s.nowText(c.id), 20, dim)
            }
            if (isFav) {
                Spacer(Modifier.width(14.dp))
                Star(fg)
            }
            if (isPlaying) {
                Spacer(Modifier.width(16.dp))
                Dot()
                Spacer(Modifier.width(8.dp))
                Txt("PLAYING", 18, fg)
            }
        }
    }
}

@Composable
private fun Info(s: LiveState, ch: Channel?) {
    ch ?: return
    Txt(channelLabel(ch).uppercase(), 22, P.w35, Modifier.at(1216, 540).width(608.dp))
    val info = s.epgNow(ch.id)
    val titleM = Modifier.at(1216, 574).width(608.dp)
    val timeM = Modifier.at(1216, 640).width(608.dp)
    when {
        info == null -> Txt("Loading programme info…", 44, P.w35, titleM)
        info.now == null && info.upcoming.isEmpty() -> {
            Txt("No programme info", 44, P.w35, titleM)
            Txt("The provider has no EPG for this channel.", 22, P.w35, timeM)
        }
        else -> {
            val cur = info.now
            if (cur != null) {
                Txt(cur.title, 44, P.w100, titleM)
                Txt(fmtTime(cur.start) + " – " + fmtTime(cur.ends), 22, P.w60, timeM)
                Txt(minLeftText(cur.ends - s.now), 22, P.w60, timeM, align = TextAlign.End)
                Box(Modifier.at(1216, 678).box(608, 3).background(P.w10))
                Box(Modifier.at(1216, 678).box((608 * progress(cur.start, cur.ends, s.now)).toInt(), 3).background(P.w100))
                Txt(cur.desc, 22, P.w60, Modifier.at(1216, 702).width(608.dp), maxLines = 3, lineSpacing = 6)
            } else {
                Txt("No programme info", 44, P.w35, titleM)
            }
            if (info.upcoming.isNotEmpty()) {
                Box(Modifier.at(1216, 816).box(608, 1).background(P.w10))
                Txt("UP NEXT", 20, P.w35, Modifier.at(1216, 840))
                info.upcoming.take(3).forEachIndexed { i, u ->
                    Txt(fmtTime(u.start), 24, P.w35, Modifier.at(1216, 878 + i * 38))
                    Txt(u.title, 24, P.w85, Modifier.at(1320, 878 + i * 38).width(504.dp))
                }
            }
        }
    }
}

// ---------- player (preview or fullscreen) ----------

@OptIn(UnstableApi::class)
@Composable
private fun PlayerArea(s: LiveState) {
    val full = s.mode == Mode.Full
    Box(if (full) Modifier.box(1920, 1080) else Modifier.at(1216, 172).box(608, 342)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setShutterBackgroundColor(AColor.BLACK)
                    setKeepContentOnPlayerReset(false)
                    player = s.player
                }
            },
            update = { it.keepScreenOn = s.playing != null && !s.failed },
            onRelease = { it.player = null },
            modifier = Modifier.fillMaxSize(),
        )
        if (!full) CornerMask(8)
        val msg = when (s.status) {
            PlayStatus.Loading -> "Loading…"
            PlayStatus.Buffering -> "Buffering…"
            else -> ""
        }
        if (msg.isNotEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Txt(msg, 22, P.w60) }
        if (!full && s.status == PlayStatus.Playing) {
            Row(Modifier.at(16, 16).box(92, 32).rounded(P.ink70, 16).padding(start = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Dot()
                Spacer(Modifier.width(8.dp))
                Txt("LIVE", 16, P.w100)
            }
        }
        if (s.failed) {
            Box(Modifier.align(Alignment.Center).box(608, 342).rounded(Color.Black, 8).outline(P.w10, 8)) {
                Txt("CHANNEL UNAVAILABLE", 20, P.w35, Modifier.at(0, 108).width(608.dp), align = TextAlign.Center)
                Txt("This channel isn't broadcasting", 30, P.w100, Modifier.at(0, 142).width(608.dp), align = TextAlign.Center)
                Txt(
                    "Tried HLS and MPEG-TS. The provider may have it offline.", 20, P.w60,
                    Modifier.at(84, 194).width(440.dp), maxLines = 2, align = TextAlign.Center,
                )
            }
        }
    }
}

/** Ink outside a rounded rect: rounds the corners of the video preview. */
@Composable
private fun CornerMask(r: Int) {
    Canvas(Modifier.fillMaxSize()) {
        val path = Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(androidx.compose.ui.geometry.Rect(Offset.Zero, size))
            addRoundRect(RoundRect(0f, 0f, size.width, size.height, CornerRadius(r.dp.toPx())))
        }
        drawPath(path, P.ink)
    }
}

// ---------- fullscreen banner ----------

@Composable
private fun Banner(s: LiveState) {
    val ch = s.playing ?: return
    Txt(fmtTime(s.now), 34, P.w100, Modifier.at(1424, 80).width(400.dp), align = TextAlign.End)
    s.neighbours()?.let { (prev, next) ->
        SurfPill("↑", prev, 380)
        SurfPill("↓", next, 446)
    }
    Row(Modifier.at(96, 722).box(940, 262).rounded(P.ink75, 12).padding(horizontal = 44.dp)) {
        if (ch.num.isNotEmpty()) {
            Txt(ch.num, 120, P.w100, Modifier.padding(top = 36.dp), medium = true)
            Spacer(Modifier.width(44.dp))
        }
        Box(Modifier.weight(1f).fillMaxHeight()) {
            Dot(modifier = Modifier.at(0, 47))
            Txt(ch.title.uppercase(), 20, P.w60, Modifier.at(22, 40).fillMaxWidth())
            val info = s.epgNow(ch.id)
            val cur = info?.now
            val title = when {
                cur != null -> cur.title
                info == null -> "Loading programme info…"
                else -> "No programme info"
            }
            Txt(title, 44, P.w100, Modifier.at(0, 74).fillMaxWidth())
            if (cur != null) {
                Txt(fmtTime(cur.start), 20, P.w60, Modifier.at(0, 140))
                Box(Modifier.offset(y = 152.dp).fillMaxWidth().padding(horizontal = 74.dp).height(3.dp).background(P.w20)) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(progress(cur.start, cur.ends, s.now)).background(P.w100))
                }
                Txt(fmtTime(cur.ends), 20, P.w60, Modifier.offset(y = 140.dp).fillMaxWidth(), align = TextAlign.End)
            }
            Box(Modifier.offset(y = 184.dp).fillMaxWidth().height(1.dp).background(P.w15))
            info?.upcoming?.firstOrNull()?.let { u ->
                Txt("Next " + fmtTime(u.start) + " · " + u.title, 22, P.w60, Modifier.offset(y = 202.dp).fillMaxWidth())
            }
        }
    }
}

/** Channel-surf hint: what Up / Down will tune to. */
@Composable
private fun SurfPill(arrow: String, ch: Channel, y: Int) {
    Box(Modifier.box(1920, 1080)) {
        Row(
            Modifier.align(Alignment.TopEnd).offset(x = (-96).dp, y = y.dp).height(62.dp).rounded(P.ink70, 12).padding(horizontal = 22.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Txt(arrow, 18, P.w60)
            Spacer(Modifier.width(16.dp))
            Txt(channelLabel(ch), 22, P.w60, Modifier.widthIn(max = 600.dp))
        }
    }
}

