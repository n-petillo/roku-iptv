sub init()
    for each id in ["header", "brand", "liveTag", "tabs", "clock", "headRule", "home", "favTitle", "favCount", "favGrid", "panels", "cats", "catSkel", "chansTitle", "chans", "chanSkel", "chansMsg", "favHint", "infoChan", "infoTitle", "infoTime", "infoLeft", "progTrack", "progFill", "infoDesc", "nextBox", "nextRows", "player", "vmask", "liveBadge", "unavail", "unavailWhy", "playerMsg", "banner", "bClock", "surfUp", "surfDown", "bNum", "bCol", "bName", "bTitle", "bStart", "bTrack", "bFill", "bEnd", "bRule", "bNext", "footer", "hints", "toast", "toastBg", "toastIcon", "toastText", "keySink", "catTimer", "epgTimer", "bannerTimer", "toastTimer", "clockTimer"]
        m[id] = m.top.FindNode(id)
    end for
    m.p = Pal()

    m.mode = "panels"      ' home | panels | full
    m.prevMode = "panels"  ' where fullscreen returns to
    m.homeFocus = "grid"   ' grid | tabs
    m.tabIdx = 0
    m.favs = []
    m.favRows = CreateObject("roSGNode", "ContentNode")
    m.favTiles = CreateObject("roSGNode", "ContentNode")
    m.favCatNode = invalid
    m.catNodes = {}        ' category id -> its ContentNode (to update counts)
    m.chanCache = {}       ' category id -> ContentNode of channels
    m.chanLoading = {}     ' category id -> true while its request is in flight
    m.curCatId = invalid
    m.pendingCat = -1      ' category index to select once categories arrive
    m.focusChansFor = ""    ' category id whose channels should take focus once shown
    m.epgCache = {}        ' stream id -> { at, list }
    m.epgPending = {}      ' stream id -> true while requested
    m.epgQueue = []
    m.epgInflight = 0
    m.tasks = {}           ' running ApiTasks, kept alive until they report
    m.taskSeq = 0
    m.infoFor = invalid    ' channel node shown in the preview panel
    m.playList = invalid
    m.playIndex = -1
    m.playListKind = ""   ' "rows" | "tiles" when zapping through favorites
    m.playing = invalid
    m.ext = "m3u8"
    m.retries = 0
    m.failed = false
    m.dialog = invalid
    m.refreshing = false   ' "Refresh channels & guide" request in flight

    m.liveTag.translation = [96 + TextWidth(m.brand) + 28, 60]
    buildSkeletons()
    buildFavHint()
    m.nextTimes = []
    m.nextTitles = []
    for i = 0 to 2
        m.nextTimes.Push(MkLabel(m.nextRows, "", 1216, 878 + i * 38, 24, m.p.w35))
        t = MkLabel(m.nextRows, "", 1320, 878 + i * 38, 24, m.p.w85)
        t.width = 504
        m.nextTitles.Push(t)
    end for
    m.lastHints = ""

    m.cats.ObserveField("itemFocused", "onCatFocused")
    m.cats.ObserveField("itemSelected", "onCatSelected")
    m.chans.ObserveField("itemFocused", "onChanFocused")
    m.chans.ObserveField("itemSelected", "onChanSelected")
    m.favGrid.ObserveField("itemSelected", "onTileSelected")
    m.player.ObserveField("state", "onPlayerState")
    m.catTimer.ObserveField("fire", "loadChannels")
    m.epgTimer.ObserveField("fire", "onEpgTimer")
    m.bannerTimer.ObserveField("fire", "hideBanner")
    m.toastTimer.ObserveField("fire", "hideToast")
    m.clockTimer.ObserveField("fire", "onClock")
    m.top.ObserveField("focusedChild", "onFocusChange")

    onClock()
    m.clockTimer.control = "start"
end sub

sub onCreds()
    m.creds = m.top.creds
    m.favKey = favKey(m.creds)
    loadFavs()
    loadCategories()
    if m.favs.Count() > 0 then showHome() else showPanels(-1, false)
end sub

sub onFocusChange()
    if not m.top.HasFocus() or m.dialog <> invalid then return
    if m.mode = "panels"
        focusPanel(m.cats)
    else if m.mode = "home" and m.homeFocus = "grid"
        m.favGrid.SetFocus(true)
    end if
end sub

sub focusPanel(list as object)
    if list.IsSameNode(m.chans) and (m.chans.content = invalid or m.chans.content.GetChildCount() = 0) then list = m.cats
    list.SetFocus(true)
    updateHints()
end sub

' ---------- skeletons / static bits ----------

sub buildSkeletons()
    widths = [220, 160, 120, 180, 140, 200, 110, 150, 230, 170]
    for i = 0 to widths.Count() - 1
        MkPoster(m.catSkel, "pkg:/images/r4.9.png", 0, i * 62 + 20, widths[i], 22, m.p.w08)
    end for
    widths = [260, 200, 310, 240, 280, 190, 300, 220]
    for i = 0 to widths.Count() - 1
        y = i * 92
        MkPoster(m.chanSkel, "pkg:/images/r4.9.png", 20, y + 34, 60, 20, m.p.w06)
        MkPoster(m.chanSkel, "pkg:/images/r4.9.png", 102, y + 17, 72, 54, m.p.w06)
        MkPoster(m.chanSkel, "pkg:/images/r4.9.png", 196, y + 22, widths[i], 22, m.p.w08)
        MkPoster(m.chanSkel, "pkg:/images/r4.9.png", 196, y + 56, 180, 16, "0xFFFFFF0D")
    end for
end sub

' "Press [play/pause] on any channel to add or remove it."
sub buildFavHint()
    a = MkLabel(m.favHint, "Press", 0, 0, 20, m.p.w35)
    x = TextWidth(a) + 10
    MkPoster(m.favHint, "pkg:/images/playpause.png", x, 4, 30, 17, m.p.w35)
    MkLabel(m.favHint, "on any channel to add or remove it.", x + 40, 0, 20, m.p.w35)
end sub

' ---------- modes ----------

sub showHome()
    if m.favs.Count() = 0
        showPanels(-1, false)
        return
    end if
    m.mode = "home"
    stopPlayback()
    m.home.visible = true
    m.panels.visible = false
    m.header.visible = true
    m.footer.visible = true
    m.liveTag.visible = false
    m.headRule.visible = false
    m.tabs.visible = true
    setPlayerVisible(false)
    if m.favGrid.content = invalid or not m.favGrid.content.IsSameNode(m.favTiles) then m.favGrid.content = m.favTiles
    m.favCount.text = m.favs.Count().ToStr()
    m.favCount.translation = [96 + TextWidth(m.favTitle) + 24, 166]
    m.homeFocus = "grid"
    m.tabIdx = 0
    renderTabs()
    m.favGrid.SetFocus(true)
    queueFavEpg()
    updateHints()
end sub

' catIndex: category to select (-1 keeps the current one); focusChans: jump into the channel list once loaded.
sub showPanels(catIndex as integer, focusChans as boolean)
    m.mode = "panels"
    m.home.visible = false
    m.panels.visible = true
    m.header.visible = true
    m.footer.visible = true
    m.liveTag.visible = true
    m.headRule.visible = true
    m.tabs.visible = false
    previewLayout()
    setPlayerVisible(true)
    m.focusChansFor = ""
    if focusChans then m.focusChansFor = "all"
    if catIndex = -2
        m.pendingCat = -2
    else if catIndex >= 0
        if m.cats.content <> invalid and m.cats.content.GetChildCount() > catIndex
            m.cats.jumpToItem = catIndex
            loadChannels()
        else
            m.pendingCat = catIndex
        end if
    end if
    if focusChans and m.chans.content <> invalid and m.chans.content.GetChildCount() > 0 and m.curCatId <> invalid
        focusPanel(m.chans)
    else
        focusPanel(m.cats)
    end if
end sub

sub renderTabs()
    while m.tabs.GetChildCount() > 0
        m.tabs.RemoveChildIndex(0)
    end while
    x = 96 + TextWidth(m.brand) + 56
    names = ["FAVORITES", "ALL CHANNELS", "CATEGORIES"]
    for i = 0 to 2
        tabFocused = (m.homeFocus = "tabs" and m.tabIdx = i)
        current = (i = 0)
        bg = invalid
        if tabFocused then bg = MkPoster(m.tabs, "pkg:/images/pill44.9.png", x - 18, 50, 0, 44, m.p.w100)
        color = m.p.w60
        if tabFocused
            color = m.p.ink
        else if current
            color = m.p.w100
        end if
        l = MkLabel(m.tabs, names[i], x, 50, 20, color)
        l.height = 44
        l.vertAlign = "center"
        w = TextWidth(l)
        if bg <> invalid then bg.width = w + 36
        if current and not tabFocused
            u = m.tabs.CreateChild("Rectangle")
            u.translation = [x, 94]
            u.width = w
            u.height = 2
            u.color = m.p.w100
        end if
        x = x + w + 40
    end for
end sub

sub activateTab()
    if m.tabIdx = 0
        m.homeFocus = "grid"
        renderTabs()
        m.favGrid.SetFocus(true)
        updateHints()
    else if m.tabIdx = 1
        showPanels(1, true)       ' All channels
    else if m.cats.content = invalid
        showPanels(-2, false)     ' resolved to the first real category once loaded
    else
        showPanels(firstRealCat(), false)
    end if
end sub

' Index of the first provider category (after Favorites and All channels).
function firstRealCat() as integer
    if m.cats.content <> invalid and m.cats.content.GetChildCount() > 2 then return 2
    return 1
end function

sub previewLayout()
    m.player.translation = [1216, 172]
    m.player.width = 608
    m.player.height = 342
    m.unavail.translation = [1216, 172]
    m.playerMsg.translation = [1216, 172]
    m.playerMsg.width = 608
    m.playerMsg.height = 342
    m.vmask.visible = true
end sub

sub fullLayout()
    m.player.translation = [0, 0]
    m.player.width = 1920
    m.player.height = 1080
    m.unavail.translation = [656, 369]
    m.playerMsg.translation = [0, 0]
    m.playerMsg.width = 1920
    m.playerMsg.height = 1080
    m.vmask.visible = false
end sub

sub setPlayerVisible(v as boolean)
    m.player.visible = v
    m.vmask.visible = v and m.mode <> "full"
    m.playerMsg.visible = v
    if not v
        m.unavail.visible = false
        m.liveBadge.visible = false
    end if
end sub

' ---------- data loading ----------

sub request(kind as string, params as object, ctx as object, timeoutMs = 20000 as integer)
    m.taskSeq = m.taskSeq + 1
    tid = "t" + m.taskSeq.ToStr()
    ctx.tid = tid
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("result", "onTaskResult")
    task.request = { kind: kind, url: ApiUrl(m.creds, params), ctx: ctx, timeoutMs: timeoutMs }
    m.tasks[tid] = { task: task, at: NowSecs(), kind: kind, ctx: ctx }
    task.control = "RUN"
end sub

sub onTaskResult(evt as object)
    res = evt.GetData()
    entry = m.tasks[res.ctx.tid]
    m.tasks.Delete(res.ctx.tid)
    if entry = invalid then return
    task = entry.task

    if res.kind = "categories"
        if res.ctx.refresh = true
            onRefreshed(res, task.content)
        else if res.ok
            onCategories(task.content, invalid)
        else
            onCategoriesFailed(res)
        end if
    else if res.kind = "streams"
        catId = res.ctx.catId
        m.chanLoading.Delete(catId)
        if res.ok
            m.chanCache[catId] = task.content
            cat = m.catNodes[catId]
            if cat <> invalid then cat.ShortDescriptionLine1 = task.content.GetChildCount().ToStr()
            if catId = m.curCatId then swapChannels(task.content)
        else if catId = m.curCatId
            if m.chans.content <> invalid and m.chans.content.GetChildCount() > 0
                showToast("Couldn't refresh channels. " + res.error, false)   ' keep the old list
            else
                m.chanSkel.visible = false
                m.chansMsg.text = "Couldn't load channels." + Chr(10) + res.error
            end if
        end if
    else if res.kind = "epg"
        sid = res.ctx.streamId
        m.epgPending.Delete(sid)
        m.epgInflight = m.epgInflight - 1
        if res.ok
            m.epgCache[sid] = { at: NowSecs(), list: res.data }
        else
            m.epgCache[sid] = { at: NowSecs() - 540, list: [] }   ' retry in about a minute
        end if
        applyEpg(sid)
        if m.infoFor <> invalid and m.infoFor.id = sid then renderInfo()
        if m.playing <> invalid and m.playing.id = sid and m.banner.visible then renderBanner()
        pumpEpg()
    end if
end sub

sub loadCategories()
    m.catSkel.visible = true
    m.chanSkel.visible = true
    m.chansTitle.text = "LOADING CHANNELS…"
    request("categories", { action: "get_live_categories" }, {})
end sub

' Category list: Favorites (pinned), All channels, then the provider's categories.
' keepId: category to stay on (refresh); invalid uses m.pendingCat.
sub onCategories(root as object, keepId as dynamic)
    fav = CreateObject("roSGNode", "ContentNode")
    fav.id = "fav"
    fav.title = "Favorites"
    fav.ShortDescriptionLine1 = m.favs.Count().ToStr()
    all = CreateObject("roSGNode", "ContentNode")
    all.id = "all"
    all.title = "All channels"
    root.InsertChild(all, 0)
    root.InsertChild(fav, 0)
    m.favCatNode = fav
    m.catNodes = {}
    for i = 0 to root.GetChildCount() - 1
        c = root.GetChild(i)
        m.catNodes[c.id] = c
    end for

    m.catSkel.visible = false
    m.cats.content = root
    idx = m.pendingCat
    if keepId <> invalid then idx = indexOfId(root, keepId)
    if idx < 0 or idx >= root.GetChildCount() then idx = firstRealCat()   ' -1 / -2: first real category
    m.pendingCat = -1
    m.cats.jumpToItem = idx
    loadChannels()
end sub

sub onCategoriesFailed(res as object)
    if res.netError
        m.top.fatal = { heading: "Cannot reach server" }
    else
        m.top.fatal = { heading: "Couldn't load channels", message: res.error }
    end if
end sub

' ---------- refresh ----------

' Re-fetches the category list, the shown channels and the guide, and reconnects the playing stream.
' Current data stays on screen until the new category list arrives; a failure only shows a toast.
sub refreshAll()
    if m.refreshing then return
    m.refreshing = true
    request("categories", { action: "get_live_categories" }, { refresh: true })
end sub

sub onRefreshed(res as object, root as object)
    m.refreshing = false
    if not res.ok
        showToast("Couldn't refresh. " + res.error, false)
        return
    end if
    keepCat = m.curCatId
    m.chanCache = {}
    m.epgCache = {}
    m.epgQueue = []
    onCategories(root, keepCat)
    ' still on the same category: fetch its channels again; the old list stays until they arrive
    if keepCat <> invalid and keepCat = m.curCatId and keepCat <> "fav" and m.chanLoading[keepCat] <> true
        m.chanLoading[keepCat] = true
        params = { action: "get_live_streams" }
        if keepCat <> "all" then params.category_id = keepCat
        request("streams", params, { catId: keepCat }, 60000)
    end if

    if m.mode = "home"
        queueFavEpg()
    else if m.chans.content <> invalid
        queueEpgAround(m.chans.content, m.chans.itemFocused)
    end if
    renderInfo()
    if m.playing <> invalid
        m.ext = credsExt()
        m.retries = 0
        m.failed = false
        m.global.playingId = m.playing.id
        startStream()
        m.epgQueue.Unshift(m.playing.id)
        pumpEpg()
    end if
    showToast("Channels & guide refreshed", true)
    updateHints()
end sub

' Index of the child with this id, or -1.
function indexOfId(list as object, id as string) as integer
    for i = 0 to list.GetChildCount() - 1
        if list.GetChild(i).id = id then return i
    end for
    return -1
end function

sub onCatFocused()
    ' the user moved on: drop any pending "focus channels" for another category
    cat = invalid
    if m.cats.content <> invalid then cat = m.cats.content.GetChild(m.cats.itemFocused)
    if cat = invalid or cat.id <> m.focusChansFor then m.focusChansFor = ""
    m.catTimer.control = "stop"
    m.catTimer.control = "start"
end sub

sub onCatSelected()
    wantChannels()
end sub

' Right / OK on a category: show its channels and move focus there (now, or once they load).
sub wantChannels()
    cat = m.cats.content.GetChild(m.cats.itemFocused)
    if cat = invalid then return
    m.focusChansFor = cat.id
    loadChannels()
    if m.curCatId = cat.id and m.chans.content <> invalid and m.chans.content.GetChildCount() > 0
        m.focusChansFor = ""
        focusPanel(m.chans)
    end if
end sub

sub loadChannels()
    m.catTimer.control = "stop"
    if m.cats.content = invalid then return
    cat = m.cats.content.GetChild(m.cats.itemFocused)
    if cat = invalid or m.curCatId = cat.id then return
    m.curCatId = cat.id

    if cat.id = "fav"
        showChannels(m.favRows, 0)
        return
    end if
    cached = m.chanCache[cat.id]
    if cached <> invalid
        showChannels(cached, 0)
        return
    end if
    m.chans.content = CreateObject("roSGNode", "ContentNode")
    m.infoFor = invalid
    renderInfo()
    m.chansMsg.text = ""
    m.favHint.visible = false
    m.chanSkel.visible = true
    m.chansTitle.text = "LOADING CHANNELS…"
    if m.chanLoading[cat.id] = true then return
    m.chanLoading[cat.id] = true
    params = { action: "get_live_streams" }
    if cat.id <> "all" then params.category_id = cat.id
    request("streams", params, { catId: cat.id }, 60000)
end sub

' A category's channels arrived: show them, staying on the focused channel when it's still listed (refresh),
' and keep zapping on the new list if the playing channel came from the old one.
sub swapChannels(content as object)
    old = m.chans.content
    if m.playing <> invalid and m.playList <> invalid and old <> invalid and m.playList.IsSameNode(old)
        i = indexOfId(content, m.playing.id)
        if i >= 0
            m.playList = content
            m.playIndex = i
            m.playing = content.GetChild(i)
        end if
    end if
    idx = 0
    ch = focusedChannel()
    if ch <> invalid then idx = indexOfId(content, ch.id)
    if idx < 0 then idx = 0
    showChannels(content, idx)
end sub

sub showChannels(content as object, idx as integer)
    m.chanSkel.visible = false
    m.chans.content = content
    n = content.GetChildCount()
    cat = m.catNodes[m.curCatId]
    title = ""
    if cat <> invalid then title = UCase(cat.title) + " · "
    if n = 1 then title = title + "1 CHANNEL" else title = title + n.ToStr() + " CHANNELS"
    SetText(m.chansTitle, title)

    isFav = (m.curCatId = "fav")
    if n = 0
        if isFav then m.chansMsg.text = "No favorites yet." else m.chansMsg.text = "No channels in this category."
        m.infoFor = invalid
        renderInfo()
    else
        m.chansMsg.text = ""
        if idx >= n then idx = n - 1
        m.chans.jumpToItem = idx
        onChanFocused()
    end if
    ' hint under a short favorites list
    m.favHint.visible = isFav and n < 8
    if n = 0 then y = 580 else y = 214 + n * 92 + 28
    m.favHint.translation = [536, y]

    if m.focusChansFor = m.curCatId and n > 0 and m.mode = "panels"
        m.focusChansFor = ""
        focusPanel(m.chans)
    end if
    updateHints()
end sub

' ---------- favorites ----------

' Favorites are stored per account so switching providers doesn't mix lists.
function favKey(c as object) as string
    raw = LCase(c.server + "_" + c.username)
    key = "favs_"
    for i = 1 to Len(raw)
        ch = Mid(raw, i, 1)
        if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") then key = key + ch
    end for
    return Left(key, 64)
end function

sub loadFavs()
    sec = CreateObject("roRegistrySection", "iptv")
    m.favs = []
    if sec.Exists(m.favKey)
        v = ParseJson(sec.Read(m.favKey))
        if Type(v) = "roArray" then m.favs = v
    end if
    syncFavs()
end sub

sub saveFavs()
    sec = CreateObject("roRegistrySection", "iptv")
    sec.Write(m.favKey, FormatJson(m.favs))
    sec.Flush()
end sub

' Rebuilds everything derived from m.favs.
sub syncFavs()
    ids = {}
    for each f in m.favs
        ids[f.id] = true
    end for
    m.global.favIds = ids
    m.favRows = buildFavNodes(false)
    m.favTiles = buildFavNodes(true)
    if m.favCatNode <> invalid then m.favCatNode.ShortDescriptionLine1 = m.favs.Count().ToStr()
    m.favCount.text = m.favs.Count().ToStr()
end sub

function buildFavNodes(isTile as boolean) as object
    root = CreateObject("roSGNode", "ContentNode")
    for each f in m.favs
        n = root.CreateChild("ContentNode")
        if isTile then n.AddFields({ prog: 0.0 })
        n.id = f.id
        n.title = AnyToStr(f.title)
        n.HDPosterUrl = AnyToStr(f.icon)
        n.ShortDescriptionLine1 = AnyToStr(f.num)
        applyNow(n)
    end for
    return root
end function

sub toggleFav(ch as dynamic)
    if ch = invalid then return
    entry = { id: ch.id, title: ch.title, num: ch.ShortDescriptionLine1, icon: ch.HDPosterUrl }
    added = FavToggle(m.favs, entry)
    saveFavs()
    syncFavs()
    ' favorites lists were rebuilt: keep zapping and the Favorites panel on the new nodes
    if m.playing <> invalid and m.playListKind <> ""
        if m.playListKind = "rows" then m.playList = m.favRows else m.playList = m.favTiles
        i = FavIndex(m.favs, m.playing.id)
        if i < 0 then i = m.playIndex
        if i >= m.playList.GetChildCount() then i = m.playList.GetChildCount() - 1
        m.playIndex = i
        if m.playList.GetChildCount() = 0 then m.playList = invalid
    end if
    if added then showToast("Added " + ch.title + " to Favorites", true) else showToast("Removed " + ch.title + " from Favorites", true)

    if m.mode = "home"
        if m.favs.Count() = 0
            showPanels(firstRealCat(), false)
            return
        end if
        idx = m.favGrid.itemFocused
        m.favGrid.content = m.favTiles
        if idx >= m.favs.Count() then idx = m.favs.Count() - 1
        m.favGrid.jumpToItem = idx
        m.favCount.translation = [96 + TextWidth(m.favTitle) + 24, 166]
    else if m.mode = "full" and m.curCatId = "fav"
        idx = 0
        if m.playIndex > 0 then idx = m.playIndex
        showChannels(m.favRows, idx)
    else if m.mode = "panels" and m.curCatId = "fav"
        idx = m.chans.itemFocused
        showChannels(m.favRows, idx)
        if m.favs.Count() = 0 then focusPanel(m.cats)
    end if
    updateHints()
end sub

' ok = false: no check mark (failures).
sub showToast(text as string, ok as boolean)
    m.toastIcon.visible = ok
    SetText(m.toastText, text)
    w = 64 + TextWidth(m.toastText) + 28
    m.toastBg.width = w
    m.toast.translation = [1824 - w, 160]
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub hideToast()
    m.toast.visible = false
end sub

' ---------- EPG ----------

function focusedChannel() as dynamic
    if m.chans.content = invalid then return invalid
    return m.chans.content.GetChild(m.chans.itemFocused)
end function

sub onChanFocused()
    m.infoFor = focusedChannel()
    renderInfo()
    updateHints()
    m.epgTimer.control = "stop"
    m.epgTimer.control = "start"
end sub

sub onEpgTimer()
    if m.mode = "panels" and m.chans.content <> invalid then queueEpgAround(m.chans.content, m.chans.itemFocused)
end sub

function needsEpg(sid as string) as boolean
    if m.epgPending[sid] = true then return false
    e = m.epgCache[sid]
    return e = invalid or NowSecs() - e.at >= 600
end function

' Replaces the queue (most important first) and starts fetching, max 3 at a time.
sub queueEpg(ids as object)
    m.epgQueue = ids
    pumpEpg()
end sub

sub pumpEpg()
    while m.epgInflight < 3 and m.epgQueue.Count() > 0
        sid = m.epgQueue.Shift()
        if needsEpg(sid)
            m.epgPending[sid] = true
            m.epgInflight = m.epgInflight + 1
            request("epg", { action: "get_short_epg", stream_id: sid, limit: 10 }, { streamId: sid })
        end if
    end while
end sub

' Focused channel first, then the rows around it so their "what's on" lines fill in.
sub queueEpgAround(list as object, idx as integer)
    ids = []
    n = list.GetChildCount()
    for each off in [0, 1, 2, 3, 4, 5, 6, 7, -1, -2]
        i = idx + off
        if i >= 0 and i < n then ids.Push(list.GetChild(i).id)
    end for
    queueEpg(ids)
end sub

sub queueFavEpg()
    ids = []
    for each f in m.favs
        ids.Push(f.id)
    end for
    queueEpg(ids)
end sub

' Splits a cached EPG list into {now, upcoming[]} relative to the current time.
function epgNow(sid as dynamic) as dynamic
    if sid = invalid then return invalid
    e = m.epgCache[sid]
    if e = invalid or e.list = invalid then return invalid
    now = NowSecs()
    cur = invalid
    upcoming = []
    for each p in e.list
        if p.ends > now
            if cur = invalid and p.start <= now
                cur = p
            else if p.start > now
                upcoming.Push(p)
            end if
        end if
    end for
    return { now: cur, upcoming: upcoming }
end function

' Sets a channel/tile node's "what's on" line (and tile progress) from the cache.
sub applyNow(n as object)
    info = epgNow(n.id)
    if info = invalid then return
    if info.now <> invalid
        n.ShortDescriptionLine2 = NowLine(info.now, NowSecs())
        if n.HasField("prog") then n.prog = Progress(info.now.start, info.now.ends, NowSecs())
    else
        n.ShortDescriptionLine2 = "No programme info"
        if n.HasField("prog") then n.prog = 0.0
    end if
end sub

sub applyEpg(sid as string)
    for each list in [m.favRows, m.favTiles]
        for i = 0 to list.GetChildCount() - 1
            n = list.GetChild(i)
            if n.id = sid then applyNow(n)
        end for
    end for
    forVisibleRows(sid)
end sub

' Applies cached EPG to channel rows near the focus (sid = invalid: all of them).
sub forVisibleRows(sid as dynamic)
    list = m.chans.content
    if list = invalid or list.IsSameNode(m.favRows) then return
    n = list.GetChildCount()
    lo = m.chans.itemFocused - 10
    if lo < 0 then lo = 0
    hi = m.chans.itemFocused + 10
    if hi > n - 1 then hi = n - 1
    for i = lo to hi
        c = list.GetChild(i)
        if sid = invalid or c.id = sid then applyNow(c)
    end for
end sub

' EPG requests that never reported (task died) give their slot back after 45s.
sub sweepTasks(now as integer)
    stale = []
    for each tid in m.tasks
        e = m.tasks[tid]
        if e.kind = "epg" and now - e.at > 45 then stale.Push(tid)
    end for
    for each tid in stale
        sid = m.tasks[tid].ctx.streamId
        m.tasks.Delete(tid)
        m.epgPending.Delete(sid)
        m.epgInflight = m.epgInflight - 1
    end for
    if m.epgInflight < 0 then m.epgInflight = 0
    if stale.Count() > 0 then pumpEpg()
end sub

sub onClock()
    now = NowSecs()
    sweepTasks(now)
    m.clock.text = FmtClock(now)
    m.bClock.text = FmtTime(now)
    for each list in [m.favRows, m.favTiles]
        for i = 0 to list.GetChildCount() - 1
            applyNow(list.GetChild(i))
        end for
    end for
    forVisibleRows(invalid)
    renderInfo()
    if m.banner.visible then renderBanner()
end sub

function channelLabel(ch as object) as string
    if ch.ShortDescriptionLine1 <> "" then return ch.ShortDescriptionLine1 + " · " + ch.title
    return ch.title
end function

sub renderInfo()
    ch = m.infoFor
    p = m.p
    m.progFill.width = 0
    m.progTrack.visible = false
    m.infoLeft.text = ""
    m.infoDesc.text = ""
    m.nextBox.visible = false
    m.infoTitle.color = p.w35
    m.infoTime.color = p.w35
    if ch = invalid
        m.infoChan.text = ""
        m.infoTitle.text = ""
        m.infoTime.text = ""
        return
    end if
    SetText(m.infoChan, UCase(channelLabel(ch)))
    info = epgNow(ch.id)
    if info = invalid
        m.infoTitle.text = "Loading programme info…"
        m.infoTime.text = ""
        return
    end if
    if info.now = invalid and info.upcoming.Count() = 0
        m.infoTitle.text = "No programme info"
        m.infoTime.text = "The provider has no EPG for this channel."
        return
    end if

    now = NowSecs()
    if info.now <> invalid
        cur = info.now
        m.infoTitle.color = p.w100
        m.infoTime.color = p.w60
        SetText(m.infoTitle, cur.title)
        m.infoTime.text = FmtTime(cur.start) + " – " + FmtTime(cur.ends)
        m.infoLeft.text = MinLeftText(cur.ends - now)
        m.progTrack.visible = true
        m.progFill.width = Int(608 * Progress(cur.start, cur.ends, now))
        SetText(m.infoDesc, cur.desc)
    else
        m.infoTitle.text = "No programme info"
        m.infoTime.text = ""
    end if

    for i = 0 to 2
        if i < info.upcoming.Count()
            u = info.upcoming[i]
            m.nextTimes[i].text = FmtTime(u.start)
            SetText(m.nextTitles[i], u.title)
        else
            m.nextTimes[i].text = ""
            m.nextTitles[i].text = ""
        end if
    end for
    m.nextBox.visible = info.upcoming.Count() > 0
end sub

' ---------- playback ----------

sub onChanSelected()
    idx = m.chans.itemSelected
    ch = m.chans.content.GetChild(idx)
    if ch = invalid then return
    if m.playing <> invalid and m.playing.id = ch.id and not m.failed
        enterFullscreen()
    else
        play(m.chans.content, idx)     ' also "Try again" after a failure
    end if
end sub

sub onTileSelected()
    idx = m.favGrid.itemSelected
    if idx < 0 or idx >= m.favTiles.GetChildCount() then return
    play(m.favTiles, idx)
    enterFullscreen()
end sub

sub play(list as object, idx as integer)
    m.playListKind = ""
    if list.IsSameNode(m.favRows) then m.playListKind = "rows"
    if list.IsSameNode(m.favTiles) then m.playListKind = "tiles"
    m.playList = list
    m.playIndex = idx
    m.playing = list.GetChild(idx)
    m.global.playingId = m.playing.id
    m.ext = credsExt()
    m.retries = 0
    m.failed = false
    startStream()
    if needsEpg(m.playing.id)
        m.epgQueue.Unshift(m.playing.id)
        pumpEpg()
    end if
    updateHints()
end sub

sub stopPlayback()
    m.player.control = "stop"
    m.playing = invalid
    m.failed = false
    m.global.playingId = ""
    m.liveBadge.visible = false
    m.unavail.visible = false
    m.playerMsg.text = ""
end sub

function credsExt() as string
    if m.creds.ext = "ts" then return "ts"
    return "m3u8"
end function

sub startStream()
    c = CreateObject("roSGNode", "ContentNode")
    c.url = StreamUrl(m.creds, m.playing.id, m.ext)
    ' .ts: leave streamFormat unset and let the player detect MPEG-TS
    if m.ext = "m3u8" then c.streamFormat = "hls"
    c.title = m.playing.title
    c.live = true
    m.player.control = "stop"
    m.player.content = c
    m.player.control = "play"
    m.unavail.visible = false
    m.liveBadge.visible = false
    m.playerMsg.text = "Loading…"
end sub

sub onPlayerState()
    state = m.player.state
    if m.playing = invalid then return
    if state = "playing"
        m.playerMsg.text = ""
        m.retries = 0
        m.failed = false
        m.liveBadge.visible = (m.mode = "panels")
    else if state = "buffering"
        m.playerMsg.text = "Buffering…"
    else if state = "error"
        if m.ext = credsExt()
            if m.ext = "m3u8" then m.ext = "ts" else m.ext = "m3u8"   ' try the other container once
            startStream()
        else
            showUnavailable()
        end if
    else if state = "finished"
        ' live streams shouldn't end; reconnect a few times
        if m.retries < 3
            m.retries = m.retries + 1
            startStream()
        else
            showUnavailable()
        end if
    end if
end sub

sub showUnavailable()
    m.failed = true
    m.global.playingId = ""
    m.player.control = "stop"
    m.playerMsg.text = ""
    m.liveBadge.visible = false
    m.unavailWhy.text = "Tried HLS and MPEG-TS. The provider may have it offline."
    m.unavail.visible = true
    updateHints()
end sub

sub zap(delta as integer)
    if m.playList = invalid then return
    n = m.playList.GetChildCount()
    if n = 0 then return
    idx = (m.playIndex + delta + n) mod n
    play(m.playList, idx)
    showBanner()
end sub

sub enterFullscreen()
    m.prevMode = m.mode
    m.mode = "full"
    m.header.visible = false
    m.panels.visible = false
    m.home.visible = false
    m.footer.visible = false
    m.liveBadge.visible = false
    setPlayerVisible(true)
    fullLayout()
    m.keySink.SetFocus(true)
    showBanner()
end sub

sub exitFullscreen()
    hideBanner()
    if m.prevMode = "home"
        showHome()
        return
    end if
    showPanels(-1, false)
    if m.playing <> invalid and not m.failed and m.player.state = "playing" then m.liveBadge.visible = true
    if m.playList <> invalid and m.chans.content <> invalid and m.chans.content.IsSameNode(m.playList)
        m.chans.jumpToItem = m.playIndex
    end if
    focusPanel(m.chans)
end sub

sub showBanner()
    renderBanner()
    m.banner.visible = true
    m.bannerTimer.control = "stop"
    m.bannerTimer.control = "start"
end sub

sub hideBanner()
    m.banner.visible = false
end sub

sub renderBanner()
    ch = m.playing
    if ch = invalid then return
    m.bNum.text = ch.ShortDescriptionLine1
    cx = 44
    if m.bNum.text <> "" then cx = 44 + TextWidth(m.bNum) + 44
    colW = 940 - cx - 44
    m.bCol.translation = [cx, 0]
    SetText(m.bName, UCase(ch.title))
    m.bName.width = colW - 22
    m.bTitle.width = colW
    m.bRule.width = colW
    m.bEnd.width = colW
    m.bNext.width = colW

    info = epgNow(ch.id)
    hasNow = info <> invalid and info.now <> invalid
    m.bStart.visible = hasNow
    m.bEnd.visible = hasNow
    m.bTrack.visible = hasNow
    m.bFill.visible = hasNow
    m.bNext.text = ""
    if hasNow
        cur = info.now
        SetText(m.bTitle, cur.title)
        m.bStart.text = FmtTime(cur.start)
        m.bEnd.text = FmtTime(cur.ends)
        m.bTrack.width = colW - 148
        m.bFill.width = Int((colW - 148) * Progress(cur.start, cur.ends, NowSecs()))
    else if info = invalid
        m.bTitle.text = "Loading programme info…"
    else
        m.bTitle.text = "No programme info"
    end if
    if info <> invalid and info.upcoming.Count() > 0
        u = info.upcoming[0]
        SetText(m.bNext, "Next " + FmtTime(u.start) + " · " + u.title)
    end if

    ' channel-surf hints: what Up / Down will tune to
    n = 0
    if m.playList <> invalid then n = m.playList.GetChildCount()
    m.surfUp.visible = n > 1
    m.surfDown.visible = n > 1
    if n > 1
        buildSurf(m.surfUp, "↑", m.playList.GetChild((m.playIndex - 1 + n) mod n), 380)
        buildSurf(m.surfDown, "↓", m.playList.GetChild((m.playIndex + 1) mod n), 446)
    end if
end sub

sub buildSurf(g as object, arrow as string, ch as object, y as integer)
    while g.GetChildCount() > 0
        g.RemoveChildIndex(0)
    end while
    bg = MkPoster(g, "pkg:/images/r12.9.png", 0, 0, 0, 62, "0x0C0C0CB3")
    a = MkLabel(g, arrow, 22, 0, 18, m.p.w60)
    a.height = 62
    a.vertAlign = "center"
    t = MkLabel(g, "", 56, 0, 22, m.p.w60)
    SetText(t, channelLabel(ch))
    t.height = 62
    t.vertAlign = "center"
    tw = TextWidth(t)
    if tw > 600 then tw = 600
    t.width = tw
    w = 56 + tw + 22
    bg.width = w
    g.translation = [1824 - w, y]
end sub

' ---------- hints ----------

sub updateHints()
    back = "Exit"
    if m.favs.Count() > 0 then back = "Favorites"
    h = []
    if m.mode = "home"
        if m.homeFocus = "tabs"
            h = [{ k: "← →", t: "Choose" }, { k: "OK", t: "Open" }, { k: "*", t: "Refresh · Log out" }, { k: "Back", t: "Exit" }]
        else
            h = [{ k: "← → ↑ ↓", t: "Move" }, { k: "OK", t: "Watch fullscreen" }, { k: "pp", t: "Remove favorite" }, { k: "*", t: "Refresh · Log out" }, { k: "Back", t: "Exit" }]
        end if
    else if m.mode = "panels"
        if m.chans.HasFocus()
            ch = focusedChannel()
            ok = "Play · again for fullscreen"
            fav = "Favorite"
            if ch <> invalid
                if m.failed and m.playing <> invalid and m.playing.id = ch.id then ok = "Try again"
                if m.global.favIds[ch.id] = true then fav = "Remove favorite"
            end if
            h = [{ k: "← →", t: "Switch panel" }, { k: "OK", t: ok }, { k: "pp", t: fav }, { k: "*", t: "Refresh · Log out" }, { k: "Back", t: back }]
        else
            h = [{ k: "← →", t: "Switch panel" }, { k: "OK", t: "Open" }, { k: "*", t: "Refresh · Log out" }, { k: "Back", t: back }]
        end if
    end if
    s = FormatJson(h)
    if s = m.lastHints then return
    m.lastHints = s
    m.hints.hints = h
end sub

' ---------- dialogs ----------

sub showDialog(title as string, message as string, buttons as object)
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = title
    dlg.message = [message]
    dlg.buttons = buttons
    dlg.ObserveField("buttonSelected", "onDialogButton")
    dlg.ObserveField("wasClosed", "onDialogClosed")
    m.dialogButtons = buttons
    m.dialogChoice = -1
    if m.mode = "panels" and m.cats.HasFocus()
        m.dialogReturn = m.cats
    else if m.mode = "panels"
        m.dialogReturn = m.chans
    else if m.mode = "home" and m.homeFocus = "grid"
        m.dialogReturn = m.favGrid
    else
        m.dialogReturn = m.keySink   ' tabs
    end if
    m.dialog = dlg
    m.top.GetScene().dialog = dlg
end sub

sub onDialogButton()
    m.dialogChoice = m.dialog.buttonSelected
    m.dialog.close = true
end sub

' Acts after the dialog is gone, so screen swaps don't race the dialog's own focus restore.
sub onDialogClosed()
    m.dialog = invalid
    choice = ""
    if m.dialogChoice >= 0 then choice = m.dialogButtons[m.dialogChoice]
    m.dialogChoice = -1
    if choice = "Exit" or choice = "Log out"
        m.player.control = "stop"
        if choice = "Exit" then m.top.exitApp = true else m.top.logout = true
        return
    end if
    m.dialogReturn.SetFocus(true)
    updateHints()
    if choice = refreshLabel() then refreshAll()
end sub

function refreshLabel() as string
    return "Refresh channels & guide"
end function

' ---------- keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.mode = "full"
        if key = "back"
            exitFullscreen()
        else if key = "up"
            zap(-1)
        else if key = "down"
            zap(1)
        else if key = "OK" or key = "options"
            if m.banner.visible then hideBanner() else showBanner()
        else if key = "play"
            toggleFav(m.playing)
        end if
        return true
    end if

    if key = "back"
        if m.mode = "panels" and m.favs.Count() > 0
            showHome()
        else
            showDialog("Exit FedSmokerTV?", "", ["Exit", "Cancel"])
        end if
        return true
    else if key = "options"
        showDialog("Options", "Signed in to " + m.creds.server, [refreshLabel(), "Log out", "Cancel"])
        return true
    end if

    if m.mode = "home"
        if m.homeFocus = "tabs"
            if key = "left" and m.tabIdx > 0
                m.tabIdx = m.tabIdx - 1
            else if key = "right" and m.tabIdx < 2
                m.tabIdx = m.tabIdx + 1
            else if key = "down"
                m.tabIdx = 0
                activateTab()
                return true
            else if key = "OK"
                activateTab()
                return true
            end if
            renderTabs()
            return true
        end if
        ' the grid didn't use the key: Up from the top row goes to the tabs
        if key = "up"
            m.homeFocus = "tabs"
            m.tabIdx = 0
            m.keySink.SetFocus(true)
            renderTabs()
            updateHints()
            return true
        else if key = "play"
            toggleFav(m.favTiles.GetChild(m.favGrid.itemFocused))
            return true
        end if
        return false
    end if

    ' panels
    if key = "right" and m.cats.HasFocus()
        wantChannels()
        return true
    else if key = "left" and m.chans.HasFocus()
        focusPanel(m.cats)
        return true
    else if key = "play" and m.chans.HasFocus()
        toggleFav(focusedChannel())
        return true
    end if
    return false
end function
