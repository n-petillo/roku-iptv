// Live TV logic (port of the Roku LiveScreen.brs). Three modes share one player:
//   Home    favorites tile grid, shown at start when favorites exist
//   Panels  categories | channels | preview + EPG
//   Full    fullscreen video with the floating now/next card
package com.npetillo.fedsmokertv

import android.util.Log
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class Mode { Home, Panels, Full }
enum class PlayStatus { Idle, Loading, Buffering, Playing, Unavailable }

data class EpgEntry(val at: Long, val list: List<Programme>)

class DialogState(val kind: String, val title: String, val message: String, val buttons: List<String>) {
    var idx by mutableIntStateOf(0)
}

const val FAV = "fav"
const val ALL = "all"

class LiveState(
    private val scope: CoroutineScope,
    private val api: Api,
    private val store: Store,
    val creds: Creds,
    val player: ExoPlayer,
    private val onLogout: () -> Unit,
    private val onExit: () -> Unit,
    private val onFatal: (heading: String, message: String?) -> Unit,
) {
    var mode by mutableStateOf(Mode.Panels)
        private set
    private var prevMode = Mode.Panels // where fullscreen returns to
    var homeOnTabs by mutableStateOf(false)
        private set
    var tabIdx by mutableIntStateOf(0)
        private set
    var gridIdx by mutableIntStateOf(0)
        private set

    val favs = mutableStateListOf<Channel>()

    /** Favorites (pinned), All channels, then the provider's categories. null while loading. */
    var cats by mutableStateOf<List<Category>?>(null)
        private set
    val catCounts = mutableStateMapOf<String, Int>()
    var catIdx by mutableIntStateOf(0)
        private set
    var chansFocused by mutableStateOf(false)
        private set
    var curCatId by mutableStateOf<String?>(null)
        private set
    private var loadedChans by mutableStateOf<List<Channel>?>(null)
    var chansError by mutableStateOf("")
        private set
    var chanIdx by mutableIntStateOf(0)
        private set
    private val chanCache = HashMap<String, List<Channel>>()
    private val chanLoading = HashSet<String>()
    private var pendingCat = -1 // category index to select once categories arrive (-2: first real one)
    private var focusChansFor = "" // category whose channels should take focus once shown

    val epg = mutableStateMapOf<String, EpgEntry>()
    private val epgPending = HashSet<String>()
    private var epgQueue = ArrayDeque<String>()
    private var epgInflight = 0

    /** Ticks every 30s so "N min left", progress bars and the clock refresh. */
    var now by mutableLongStateOf(nowSecs())
        private set

    var playing by mutableStateOf<Channel?>(null)
        private set
    private var playSrc: String? = null // category id the playing channel was started from (or FAV)
    var playIdx by mutableIntStateOf(-1)
        private set
    private var ext = "m3u8"
    private var retries = 0
    var failed by mutableStateOf(false)
        private set
    var status by mutableStateOf(PlayStatus.Idle)
        private set
    private var backgrounded = false

    var banner by mutableStateOf(false)
        private set
    var toast by mutableStateOf<String?>(null)
        private set
    /** false: failure toast, drawn without the check mark. */
    var toastOk by mutableStateOf(true)
        private set
    var dialog by mutableStateOf<DialogState?>(null)
        private set

    private var catJob: Job? = null
    private var epgJob: Job? = null
    private var bannerJob: Job? = null
    private var toastJob: Job? = null
    private var clockJob: Job? = null
    private val jobs = ArrayList<Job>()
    private var refreshing = false // "Refresh" request in flight

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) = onPlayerState(state)
        override fun onPlayerError(error: PlaybackException) = onPlayerFailed(error)
    }

    fun start() {
        player.addListener(listener)
        favs.addAll(store.loadFavs(creds))
        clockJob = scope.launch {
            while (isActive) {
                now = nowSecs()
                delay(30_000 - System.currentTimeMillis() % 30_000)
            }
        }
        loadCategories()
        if (favs.isNotEmpty()) showHome() else showPanels(-1, false)
    }

    fun dispose() {
        player.removeListener(listener)
        player.stop()
        player.clearMediaItems()
        for (j in listOf(catJob, epgJob, bannerJob, toastJob, clockJob)) j?.cancel()
        jobs.forEach { it.cancel() }
    }

    private fun launch(block: suspend CoroutineScope.() -> Unit) {
        jobs.removeAll { !it.isActive }
        jobs.add(scope.launch(block = block))
    }

    // ---------- derived ----------

    /** Channels in the list panel: live favorites, or the loaded category. null = loading. */
    val shownChans: List<Channel>?
        get() = if (curCatId == FAV) favs else loadedChans

    fun focusedChannel(): Channel? = shownChans?.getOrNull(chanIdx)

    private fun listFor(src: String?): List<Channel>? = when (src) {
        null -> null
        FAV -> favs
        else -> chanCache[src]
    }

    fun catCount(id: String): Int? = if (id == FAV) favs.size else catCounts[id]

    fun isFav(id: String) = favIndex(favs, id) >= 0

    /** Splits the cached EPG into {now, upcoming}; null until it has been fetched. */
    fun epgNow(id: String?): EpgNow? {
        val e = epg[id ?: return null] ?: return null
        return epgSplit(e.list, now)
    }

    /** The "what's on" line for a row or tile. */
    fun nowText(id: String): String {
        val info = epgNow(id) ?: return ""
        return if (info.now != null) nowLine(info.now, now) else "No programme info"
    }

    fun neighbours(): Pair<Channel, Channel>? {
        val list = listFor(playSrc) ?: return null
        val n = list.size
        if (n < 2 || playIdx < 0) return null
        return list[(playIdx - 1 + n) % n] to list[(playIdx + 1) % n]
    }

    fun firstRealCat(): Int = if ((cats?.size ?: 0) > 2) 2 else 1

    // ---------- modes ----------

    private fun showHome() {
        if (favs.isEmpty()) {
            showPanels(-1, false)
            return
        }
        mode = Mode.Home
        stopPlayback()
        homeOnTabs = false
        tabIdx = 0
        gridIdx = gridIdx.coerceIn(0, favs.size - 1)
        queueEpg(favs.map { it.id })
    }

    /** catIndex: category to select (-1 keeps the current one); focusChans: jump into the channel list once loaded. */
    private fun showPanels(catIndex: Int, focusChans: Boolean) {
        mode = Mode.Panels
        focusChansFor = if (focusChans) ALL else ""
        val c = cats
        if (catIndex == -2) {
            pendingCat = -2
        } else if (catIndex >= 0) {
            if (c != null && c.size > catIndex) {
                catIdx = catIndex
                loadChannels()
            } else {
                pendingCat = catIndex
            }
        }
        chansFocused = focusChans && !shownChans.isNullOrEmpty() && curCatId != null
    }

    private fun activateTab() {
        when (tabIdx) {
            0 -> homeOnTabs = false
            1 -> showPanels(1, true) // All channels
            else -> if (cats == null) showPanels(-2, false) else showPanels(firstRealCat(), false)
        }
    }

    // ---------- data loading ----------

    private fun loadCategories() {
        launch {
            when (val r = api.categories(creds)) {
                is ApiResult.Ok -> onCategories(r.value, null)
                is ApiResult.Err ->
                    if (r.netError) onFatal("Cannot reach server", null) else onFatal("Couldn't load channels", r.error)
            }
        }
    }

    /** keepId: category to stay on (refresh); null uses pendingCat. */
    private fun onCategories(list: List<Category>, keepId: String?) {
        val all = ArrayList<Category>(list.size + 2)
        all.add(Category(FAV, "Favorites"))
        all.add(Category(ALL, "All channels"))
        all.addAll(list)
        cats = all
        var idx = if (keepId != null) all.indexOfFirst { it.id == keepId } else pendingCat
        if (idx < 0 || idx >= all.size) idx = firstRealCat()
        pendingCat = -1
        catIdx = idx
        loadChannels()
    }

    // ---------- refresh ----------

    /**
     * Re-fetches the category list, the shown channels and the guide, and reconnects the playing stream.
     * Current data stays on screen until the new category list arrives; a failure only shows a toast.
     */
    private fun refresh() {
        if (refreshing) return
        refreshing = true
        launch {
            val r = api.categories(creds)
            refreshing = false
            when (r) {
                is ApiResult.Ok -> onRefreshed(r.value)
                is ApiResult.Err -> showToast("Couldn't refresh. ${r.error}", ok = false)
            }
        }
    }

    private fun onRefreshed(list: List<Category>) {
        val keepCat = curCatId
        chanCache.clear()
        catCounts.clear()
        epg.clear()
        epgQueue.clear()
        onCategories(list, keepCat)
        // still on the same category: fetch its channels again; the old list stays until they arrive
        if (keepCat != null && keepCat == curCatId && keepCat != FAV) fetchChannels(keepCat)

        if (mode == Mode.Home) queueEpg(favs.map { it.id }) else shownChans?.let { queueEpgAround(it, chanIdx) }
        playing?.let {
            ext = creds.ext
            retries = 0
            failed = false
            startStream()
            epgQueue.addFirst(it.id)
            pumpEpg()
        }
        showToast("Channels & guide refreshed")
    }

    private fun onCatFocused() {
        // the user moved on: drop any pending "focus channels" for another category
        if (cats?.getOrNull(catIdx)?.id != focusChansFor) focusChansFor = ""
        catJob?.cancel()
        catJob = scope.launch {
            delay(350)
            loadChannels()
        }
    }

    /** Right / OK on a category: show its channels and move focus there (now, or once they load). */
    private fun wantChannels() {
        val cat = cats?.getOrNull(catIdx) ?: return
        focusChansFor = cat.id
        loadChannels()
        if (curCatId == cat.id && !shownChans.isNullOrEmpty()) {
            focusChansFor = ""
            chansFocused = true
        }
    }

    private fun loadChannels() {
        catJob?.cancel()
        val cat = cats?.getOrNull(catIdx) ?: return
        if (curCatId == cat.id) return
        curCatId = cat.id
        chansError = ""
        if (cat.id == FAV) {
            showChannels(0)
            return
        }
        chanCache[cat.id]?.let {
            loadedChans = it
            showChannels(0)
            return
        }
        loadedChans = null
        fetchChannels(cat.id)
    }

    /** Loads a category's channels; when shown, stays on the focused channel if it's still listed (refresh). */
    private fun fetchChannels(catId: String) {
        if (!chanLoading.add(catId)) return
        launch {
            val r = api.streams(creds, if (catId == ALL) null else catId)
            chanLoading.remove(catId)
            when (r) {
                is ApiResult.Ok -> {
                    chanCache[catId] = r.value
                    catCounts[catId] = r.value.size
                    val p = playing
                    if (p != null && playSrc == catId) {
                        val i = r.value.indexOfFirst { it.id == p.id }
                        if (i >= 0) playIdx = i
                    }
                    if (catId == curCatId) {
                        val keepId = focusedChannel()?.id
                        loadedChans = r.value
                        showChannels(maxOf(0, r.value.indexOfFirst { it.id == keepId }))
                    }
                }
                is ApiResult.Err -> if (catId == curCatId) {
                    if (!loadedChans.isNullOrEmpty()) {
                        showToast("Couldn't refresh channels. ${r.error}", ok = false) // keep the old list
                    } else {
                        loadedChans = emptyList()
                        chansError = "Couldn't load channels.\n" + r.error
                    }
                }
            }
        }
    }

    private fun showChannels(idx: Int) {
        val n = shownChans?.size ?: 0
        chanIdx = if (n == 0) 0 else idx.coerceIn(0, n - 1)
        if (n > 0) onChanFocused()
        if (n == 0) chansFocused = false
        if (focusChansFor == curCatId && n > 0 && mode == Mode.Panels) {
            focusChansFor = ""
            chansFocused = true
        }
    }

    // ---------- favorites ----------

    private fun toggleFav(ch: Channel?) {
        ch ?: return
        val added = favToggle(favs, Channel(ch.id, ch.title, ch.num, ch.icon))
        val snapshot = favs.toList()
        launch { store.saveFavs(creds, snapshot) }
        // keep zapping through favorites on the right index
        val p = playing
        if (p != null && playSrc == FAV) {
            var i = favIndex(favs, p.id)
            if (i < 0) i = playIdx
            playIdx = i.coerceAtMost(favs.size - 1)
            if (favs.isEmpty()) playSrc = null
        }
        showToast(if (added) "Added ${ch.title} to Favorites" else "Removed ${ch.title} from Favorites")

        when {
            mode == Mode.Home -> {
                if (favs.isEmpty()) {
                    showPanels(firstRealCat(), false)
                    return
                }
                gridIdx = gridIdx.coerceAtMost(favs.size - 1)
            }
            mode == Mode.Full && curCatId == FAV -> showChannels(maxOf(playIdx, 0))
            mode == Mode.Panels && curCatId == FAV -> showChannels(chanIdx)
        }
    }

    private fun showToast(text: String, ok: Boolean = true) {
        toast = text
        toastOk = ok
        toastJob?.cancel()
        toastJob = scope.launch {
            delay(2500)
            toast = null
        }
    }

    // ---------- EPG ----------

    private fun onChanFocused() {
        epgJob?.cancel()
        epgJob = scope.launch {
            delay(400)
            val list = shownChans
            if (mode == Mode.Panels && list != null) queueEpgAround(list, chanIdx)
        }
    }

    private fun needsEpg(id: String): Boolean {
        if (id in epgPending) return false
        val e = epg[id] ?: return true
        return nowSecs() - e.at >= 600
    }

    /** Replaces the queue (most important first) and starts fetching, max 3 at a time. */
    private fun queueEpg(ids: List<String>) {
        epgQueue = ArrayDeque(ids)
        pumpEpg()
    }

    private fun pumpEpg() {
        while (epgInflight < 3 && epgQueue.isNotEmpty()) {
            val id = epgQueue.removeFirst()
            if (!needsEpg(id)) continue
            epgPending.add(id)
            epgInflight++
            launch {
                try {
                    val r = api.shortEpg(creds, id)
                    epg[id] = when (r) {
                        is ApiResult.Ok -> EpgEntry(nowSecs(), r.value)
                        is ApiResult.Err -> EpgEntry(nowSecs() - 540, emptyList()) // retry in about a minute
                    }
                } finally {
                    epgPending.remove(id)
                    epgInflight--
                }
                pumpEpg()
            }
        }
    }

    /** Focused channel first, then the rows around it so their "what's on" lines fill in. */
    private fun queueEpgAround(list: List<Channel>, idx: Int) {
        val ids = listOf(0, 1, 2, 3, 4, 5, 6, 7, -1, -2).mapNotNull { list.getOrNull(idx + it)?.id }
        queueEpg(ids)
    }

    // ---------- playback ----------

    private fun onChanSelected() {
        val ch = focusedChannel() ?: return
        if (playing?.id == ch.id && !failed) enterFullscreen() else play(curCatId, chanIdx) // also "Try again"
    }

    private fun play(src: String?, idx: Int) {
        val list = listFor(src) ?: return
        val ch = list.getOrNull(idx) ?: return
        playSrc = src
        playIdx = idx
        playing = ch
        ext = creds.ext
        retries = 0
        failed = false
        startStream()
        if (needsEpg(ch.id)) {
            epgQueue.addFirst(ch.id)
            pumpEpg()
        }
    }

    private fun stopPlayback() {
        player.stop()
        player.clearMediaItems()
        playing = null
        failed = false
        status = PlayStatus.Idle
    }

    private fun startStream() {
        val ch = playing ?: return
        val url = streamUrl(creds, ch.id, ext)
        Log.d(TAG, "play ${ch.id} as $ext")
        val item = MediaItem.Builder()
            .setUri(url)
            .setMimeType(if (ext == "m3u8") MimeTypes.APPLICATION_M3U8 else MimeTypes.VIDEO_MP2T)
            .build()
        player.setMediaItem(item)
        player.prepare()
        player.playWhenReady = true
        status = PlayStatus.Loading
    }

    private fun onPlayerState(state: Int) {
        if (playing == null || failed) return
        when (state) {
            Player.STATE_READY -> {
                status = PlayStatus.Playing
                retries = 0
            }
            Player.STATE_BUFFERING -> if (status == PlayStatus.Playing) status = PlayStatus.Buffering
            Player.STATE_ENDED -> {
                // live streams shouldn't end; reconnect a few times
                if (retries < 3) {
                    retries++
                    startStream()
                } else {
                    showUnavailable()
                }
            }
        }
    }

    @OptIn(UnstableApi::class)
    private fun onPlayerFailed(e: PlaybackException) {
        if (playing == null || failed) return
        Log.w(TAG, "playback error ${e.errorCodeName} ($ext): ${e.message}")
        when {
            e.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> {
                player.seekToDefaultPosition()
                player.prepare()
            }
            // it was playing fine: treat like a dropped connection
            status == PlayStatus.Playing || status == PlayStatus.Buffering -> if (retries < 3) {
                retries++
                startStream()
            } else {
                showUnavailable()
            }
            ext == creds.ext -> {
                ext = if (ext == "m3u8") "ts" else "m3u8" // try the other container once
                startStream()
            }
            else -> showUnavailable()
        }
    }

    private fun showUnavailable() {
        failed = true
        player.stop()
        status = PlayStatus.Unavailable
    }

    private fun zap(delta: Int) {
        val list = listFor(playSrc) ?: return
        val n = list.size
        if (n == 0) return
        play(playSrc, ((playIdx + delta) % n + n) % n)
        showBanner()
    }

    private fun enterFullscreen() {
        prevMode = mode
        mode = Mode.Full
        showBanner()
    }

    private fun exitFullscreen() {
        banner = false
        if (prevMode == Mode.Home) {
            showHome()
            return
        }
        showPanels(-1, false)
        if (playSrc != null && playSrc == curCatId && playIdx >= 0) chanIdx = playIdx.coerceAtMost((shownChans?.size ?: 1) - 1)
        chansFocused = !shownChans.isNullOrEmpty()
    }

    private fun showBanner() {
        banner = true
        bannerJob?.cancel()
        bannerJob = scope.launch {
            delay(5000)
            banner = false
        }
    }

    fun onBackground() {
        backgrounded = true
        if (playing != null) player.stop()
    }

    fun onForeground() {
        if (!backgrounded) return
        backgrounded = false
        if (playing != null && !failed) startStream()
    }

    // ---------- dialogs ----------

    private fun showDialog(d: DialogState) {
        dialog = d
    }

    private fun onDialogKey(d: DialogState, k: K) {
        when (k) {
            K.Left -> if (d.idx > 0) d.idx--
            K.Right -> if (d.idx < d.buttons.size - 1) d.idx++
            K.Back -> dialog = null
            K.Ok -> {
                dialog = null
                when (d.buttons[d.idx]) {
                    "Exit" -> { stopPlayback(); onExit() }
                    "Log out" -> { stopPlayback(); onLogout() }
                    "Refresh" -> refresh()
                }
            }
            else -> {}
        }
    }

    private fun exitDialog() = showDialog(
        DialogState("exit", "Exit FedSmokerTV?", "Signed in to ${creds.server} as ${creds.username}", listOf("Exit", "Cancel", "Refresh", "Log out")),
    )

    private fun accountDialog() = showDialog(
        DialogState("options", "Options", "Signed in to ${creds.server} as ${creds.username}", listOf("Refresh", "Log out", "Cancel")),
    )

    // ---------- keys ----------

    fun onKey(k: K): Boolean {
        dialog?.let {
            onDialogKey(it, k)
            return true
        }

        if (mode == Mode.Full) {
            when (k) {
                K.Back -> exitFullscreen()
                K.Up, K.ChUp -> zap(-1)
                K.Down, K.ChDown -> zap(1)
                K.Ok, K.Menu -> if (banner) banner = false else showBanner()
                K.LongOk, K.PlayPause -> toggleFav(playing)
                else -> {}
            }
            return true
        }

        when (k) {
            K.Back -> {
                if (mode == Mode.Panels && favs.isNotEmpty()) showHome() else exitDialog()
                return true
            }
            K.Menu -> {
                accountDialog()
                return true
            }
            else -> {}
        }

        if (mode == Mode.Home) {
            if (homeOnTabs) {
                when (k) {
                    K.Left -> if (tabIdx > 0) tabIdx--
                    K.Right -> if (tabIdx < 2) tabIdx++
                    K.Down -> { tabIdx = 0; activateTab() }
                    K.Ok -> activateTab()
                    else -> {}
                }
                return true
            }
            val n = favs.size
            when (k) {
                K.Left -> if (gridIdx % 4 > 0) gridIdx--
                K.Right -> if (gridIdx % 4 < 3 && gridIdx + 1 < n) gridIdx++
                K.Up -> if (gridIdx >= 4) gridIdx -= 4 else { homeOnTabs = true; tabIdx = 0 }
                K.Down -> if (gridIdx / 4 < (n - 1) / 4) gridIdx = minOf(gridIdx + 4, n - 1)
                K.Ok -> if (gridIdx < n) { play(FAV, gridIdx); enterFullscreen() }
                K.LongOk, K.PlayPause -> toggleFav(favs.getOrNull(gridIdx))
                else -> {}
            }
            return true
        }

        // panels
        if (!chansFocused) {
            val n = cats?.size ?: 0
            when (k) {
                K.Up -> if (catIdx > 0) { catIdx--; onCatFocused() }
                K.Down -> if (catIdx < n - 1) { catIdx++; onCatFocused() }
                K.Right, K.Ok -> wantChannels()
                else -> {}
            }
            return true
        }
        val n = shownChans?.size ?: 0
        when (k) {
            K.Up -> if (chanIdx > 0) { chanIdx--; onChanFocused() }
            K.Down -> if (chanIdx < n - 1) { chanIdx++; onChanFocused() }
            K.ChUp -> if (n > 0) { chanIdx = maxOf(0, chanIdx - 8); onChanFocused() }
            K.ChDown -> if (n > 0) { chanIdx = minOf(n - 1, chanIdx + 8); onChanFocused() }
            K.Left -> chansFocused = false
            K.Ok -> onChanSelected()
            K.LongOk, K.PlayPause -> toggleFav(focusedChannel())
            else -> {}
        }
        return true
    }
}
