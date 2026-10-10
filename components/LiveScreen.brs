sub init()
    for each id in ["panels", "clock", "cats", "chans", "chansTitle", "chansMsg", "infoTitle", "nowTime", "progFill", "nowTitle", "nowDesc", "nextList", "player", "playerMsg", "banner", "bName", "bClock", "bNow", "bProg", "bNext", "catTimer", "epgTimer", "bannerTimer", "clockTimer"]
        m[id] = m.top.FindNode(id)
    end for

    m.chanCache = {}      ' category id -> ContentNode of channels
    m.chanLoading = {}    ' category id -> true while its request is in flight
    m.catsLoading = false
    m.epgCache = {}       ' stream id -> { at, list }
    m.tasks = {}          ' running ApiTasks, kept alive until they report
    m.taskSeq = 0
    m.curCatId = invalid
    m.epgFor = invalid    ' stream id whose EPG panel 3 is showing
    m.fullscreen = false
    m.playList = invalid
    m.playIndex = -1
    m.playing = invalid
    m.ext = "m3u8"
    m.retries = 0

    m.cats.ObserveField("itemFocused", "onCatFocused")
    m.cats.ObserveField("itemSelected", "onCatSelected")
    m.chans.ObserveField("itemFocused", "onChanFocused")
    m.chans.ObserveField("itemSelected", "onChanSelected")
    m.player.ObserveField("state", "onPlayerState")
    m.catTimer.ObserveField("fire", "loadChannels")
    m.epgTimer.ObserveField("fire", "fetchFocusedEpg")
    m.bannerTimer.ObserveField("fire", "hideBanner")
    m.clockTimer.ObserveField("fire", "onClock")
    m.top.ObserveField("focusedChild", "onFocusChange")

    onClock()
    m.clockTimer.control = "start"
end sub

sub onCreds()
    m.creds = m.top.creds
    loadCategories()
end sub

sub onFocusChange()
    if m.top.HasFocus() and not m.fullscreen then focusPanel(m.cats)
end sub

sub focusPanel(list as object)
    if list.IsSameNode(m.chans) and (m.chans.content = invalid or m.chans.content.GetChildCount() = 0) then list = m.cats
    list.SetFocus(true)
end sub

' ---------- data loading ----------

sub request(kind as string, params as object, ctx as object, timeoutMs = 20000 as integer)
    m.taskSeq = m.taskSeq + 1
    tid = "t" + m.taskSeq.ToStr()
    ctx.tid = tid
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("result", "onTaskResult")
    task.request = { kind: kind, url: ApiUrl(m.creds, params), ctx: ctx, timeoutMs: timeoutMs }
    m.tasks[tid] = task
    task.control = "RUN"
end sub

sub onTaskResult(evt as object)
    res = evt.GetData()
    task = m.tasks[res.ctx.tid]
    m.tasks.Delete(res.ctx.tid)
    if task = invalid then return

    if res.kind = "categories"
        m.catsLoading = false
        if res.ok
            m.cats.content = task.content
            m.cats.jumpToItem = 0
            loadChannels()
        else
            ' a single "Retry" item, so OK always lands on a real list item
            retry = CreateObject("roSGNode", "ContentNode")
            item = retry.CreateChild("ContentNode")
            item.id = "retry"
            item.title = "Retry"
            m.cats.content = retry
            m.chansMsg.text = "Couldn't load categories: " + res.error + Chr(10) + "Select Retry on the left."
        end if
    else if res.kind = "streams"
        catId = res.ctx.catId
        m.chanLoading.Delete(catId)
        if res.ok
            m.chanCache[catId] = task.content
            if catId = m.curCatId then showChannels(task.content)
        else if catId = m.curCatId
            m.chansMsg.text = "Couldn't load channels: " + res.error
        end if
    else if res.kind = "epg"
        sid = res.ctx.streamId
        if res.ok
            m.epgCache[sid] = { at: NowSecs(), list: res.data }
        else
            m.epgCache[sid] = { at: NowSecs() - 540, list: [] }   ' retry in about a minute
        end if
        if sid = m.epgFor then renderEpg()
        if m.playing <> invalid and sid = m.playing.id then renderBanner()
    end if
end sub

sub loadCategories()
    if m.catsLoading then return
    m.catsLoading = true
    m.curCatId = invalid
    m.chansMsg.text = "Loading categories..."
    request("categories", { action: "get_live_categories" }, {})
end sub

sub onCatFocused()
    m.catTimer.control = "stop"
    m.catTimer.control = "start"
end sub

sub onCatSelected()
    cat = m.cats.content.GetChild(m.cats.itemSelected)
    if cat <> invalid and cat.id = "retry"
        loadCategories()
        return
    end if
    focusPanel(m.chans)
end sub

sub loadChannels()
    m.catTimer.control = "stop"
    if m.cats.content = invalid then return
    cat = m.cats.content.GetChild(m.cats.itemFocused)
    if cat = invalid or cat.id = "retry" then return
    if m.curCatId = cat.id then return
    m.curCatId = cat.id
    m.chansTitle.text = "CHANNELS  -  " + UCase(cat.title)

    cached = m.chanCache[cat.id]
    if cached <> invalid
        showChannels(cached)
        return
    end if
    m.chans.content = CreateObject("roSGNode", "ContentNode")
    m.chansMsg.text = "Loading channels..."
    if m.chanLoading[cat.id] = true then return
    m.chanLoading[cat.id] = true
    params = { action: "get_live_streams" }
    if cat.id <> "all" then params.category_id = cat.id
    request("streams", params, { catId: cat.id }, 60000)
end sub

sub showChannels(content as object)
    m.chans.content = content
    if content.GetChildCount() = 0
        m.chansMsg.text = "No channels in this category."
    else
        m.chansMsg.text = ""
        m.chans.jumpToItem = 0
        onChanFocused()
    end if
end sub

' ---------- EPG ----------

function focusedChannel() as dynamic
    if m.chans.content = invalid then return invalid
    return m.chans.content.GetChild(m.chans.itemFocused)
end function

sub onChanFocused()
    ch = focusedChannel()
    if ch = invalid then return
    m.epgFor = ch.id
    m.infoTitle.text = channelLabel(ch)
    renderEpg()
    m.epgTimer.control = "stop"
    m.epgTimer.control = "start"
end sub

sub fetchFocusedEpg()
    if m.epgFor <> invalid then ensureEpg(m.epgFor)
end sub

' Requests EPG for a stream unless a fresh copy (< 10 min) is cached.
sub ensureEpg(sid as string)
    e = m.epgCache[sid]
    if e <> invalid and NowSecs() - e.at < 600 then return
    m.epgCache[sid] = { at: NowSecs(), list: currentList(e) }  ' marks in-flight so we don't re-request
    request("epg", { action: "get_short_epg", stream_id: sid, limit: 10 }, { streamId: sid })
end sub

function currentList(e as dynamic) as object
    if e = invalid then return invalid
    return e.list
end function

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

sub renderEpg()
    info = epgNow(m.epgFor)
    if info = invalid
        setNow(invalid, "Loading programme info...")
        m.nextList.text = ""
        return
    end if
    if info.now = invalid and info.upcoming.Count() = 0
        setNow(invalid, "No programme information")
        m.nextList.text = ""
        return
    end if
    setNow(info.now, "No programme information")
    lines = ""
    for i = 0 to info.upcoming.Count() - 1
        if i >= 4 then exit for
        p = info.upcoming[i]
        if lines <> "" then lines = lines + Chr(10)
        lines = lines + FmtTime(p.start) + "   " + p.title
    end for
    m.nextList.text = lines
end sub

sub setNow(p as dynamic, emptyText as string)
    if p = invalid
        m.nowTime.text = ""
        m.nowTitle.text = emptyText
        m.nowDesc.text = ""
        m.progFill.width = 0
        return
    end if
    m.nowTime.text = "NOW   " + FmtTime(p.start) + " - " + FmtTime(p.ends)
    m.nowTitle.text = p.title
    m.nowDesc.text = p.desc
    m.progFill.width = Int(710 * Progress(p.start, p.ends, NowSecs()))
end sub

sub onClock()
    t = FmtTime(NowSecs())
    m.clock.text = t
    m.bClock.text = t
    renderEpg()
    if m.banner.visible then renderBanner()
end sub

' ---------- playback ----------

sub onChanSelected()
    idx = m.chans.itemSelected
    ch = m.chans.content.GetChild(idx)
    if ch = invalid then return
    if m.playing <> invalid and m.playing.id = ch.id
        enterFullscreen()
    else
        play(m.chans.content, idx)
    end if
end sub

sub play(list as object, idx as integer)
    m.playList = list
    m.playIndex = idx
    m.playing = list.GetChild(idx)
    m.ext = credsExt()
    m.retries = 0
    startStream()
    ensureEpg(m.playing.id)
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
    m.playerMsg.text = "Loading..."
end sub

sub onPlayerState()
    state = m.player.state
    if state = "playing"
        m.playerMsg.text = ""
        m.retries = 0
    else if state = "buffering"
        m.playerMsg.text = "Buffering..."
    else if state = "error"
        if m.ext = credsExt()
            if m.ext = "m3u8" then m.ext = "ts" else m.ext = "m3u8"   ' try the other container once
            startStream()
        else
            m.playerMsg.text = "Stream unavailable" + Chr(10) + m.player.errorMsg
        end if
    else if state = "finished" and m.playing <> invalid
        ' live streams shouldn't end; reconnect a few times
        if m.retries < 3
            m.retries = m.retries + 1
            startStream()
        else
            m.playerMsg.text = "Stream ended."
        end if
    end if
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
    m.fullscreen = true
    m.panels.visible = false
    m.player.translation = [0, 0]
    m.player.width = 1920
    m.player.height = 1080
    m.playerMsg.translation = [0, 500]
    m.playerMsg.width = 1920
    m.top.SetFocus(true)
    showBanner()
end sub

sub exitFullscreen()
    m.fullscreen = false
    hideBanner()
    m.player.translation = [1120, 110]
    m.player.width = 760
    m.player.height = 428
    m.playerMsg.translation = [1120, 300]
    m.playerMsg.width = 760
    m.panels.visible = true
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
    if m.playing = invalid then return
    m.bName.text = channelLabel(m.playing)
    info = epgNow(m.playing.id)
    m.bNow.text = ""
    m.bNext.text = ""
    m.bProg.width = 0
    if info = invalid then return
    if info.now <> invalid
        p = info.now
        m.bNow.text = FmtTime(p.start) + " - " + FmtTime(p.ends) + "    " + p.title
        m.bProg.width = Int(1000 * Progress(p.start, p.ends, NowSecs()))
    else
        m.bNow.text = "No programme information"
    end if
    if info.upcoming.Count() > 0
        p = info.upcoming[0]
        m.bNext.text = "NEXT   " + FmtTime(p.start) + "    " + p.title
    end if
end sub

function channelLabel(ch as object) as string
    if ch.ShortDescriptionLine1 <> "" then return ch.ShortDescriptionLine1 + "   " + ch.title
    return ch.title
end function

' ---------- dialogs ----------

sub showDialog(kind as string, title as string, message as string, buttons as object)
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = title
    dlg.message = [message]
    dlg.buttons = buttons
    dlg.ObserveField("buttonSelected", "onDialogButton")
    dlg.ObserveField("wasClosed", "onDialogClosed")
    m.dialogKind = kind
    m.dialogChoice = -1
    m.dialogReturn = m.chans
    if m.cats.HasFocus() then m.dialogReturn = m.cats
    m.dialog = dlg
    m.top.GetScene().dialog = dlg
end sub

sub onDialogButton()
    dlg = m.dialog
    kind = m.dialogKind
    m.dialogChoice = dlg.buttonSelected
    dlg.close = true
end sub

' Acts after the dialog is gone, so screen swaps don't race the dialog's own focus restore.
sub onDialogClosed()
    m.dialog = invalid
    if m.dialogChoice = 0
        m.dialogChoice = -1
        m.player.control = "stop"
        if m.dialogKind = "exit"
            m.top.exitApp = true
        else if m.dialogKind = "logout"
            m.top.logout = true
        end if
        return
    end if
    if m.fullscreen then m.top.SetFocus(true) else focusPanel(m.dialogReturn)
end sub

' ---------- keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.fullscreen
        if key = "back"
            exitFullscreen()
        else if key = "up"
            zap(-1)
        else if key = "down"
            zap(1)
        else if key = "OK" or key = "options"
            if m.banner.visible then hideBanner() else showBanner()
        end if
        return true
    end if

    if key = "right" and m.cats.HasFocus()
        focusPanel(m.chans)
        return true
    else if key = "left" and m.chans.HasFocus()
        m.cats.SetFocus(true)
        return true
    else if key = "back"
        showDialog("exit", "Exit IPTV Live?", "", ["Exit", "Cancel"])
        return true
    else if key = "options"
        showDialog("logout", "Account", "Signed in to " + m.creds.server, ["Log out", "Cancel"])
        return true
    end if
    return false
end function
