sub init()
    for each id in ["fill", "num", "tile", "abbr", "logo", "name", "now", "star", "playing", "playText"]
        m[id] = m.top.FindNode(id)
    end for
    m.content = invalid
    m.logo.ObserveField("loadStatus", "onLogoStatus")
    m.global.ObserveFieldScoped("playingId", "render")
    m.global.ObserveFieldScoped("favIds", "render")
end sub

sub onContent()
    if m.content <> invalid then m.content.UnobserveFieldScoped("ShortDescriptionLine2")
    m.content = m.top.itemContent
    if m.content = invalid then return
    m.content.ObserveFieldScoped("ShortDescriptionLine2", "render")
    m.abbr.text = Abbrev(m.content.title)
    m.logo.uri = m.content.HDPosterUrl
    onLogoStatus()
    render()
end sub

' show initials until (or instead of) the logo
sub onLogoStatus()
    m.abbr.visible = (m.logo.uri = "" or m.logo.loadStatus <> "ready")
end sub

sub render()
    c = m.content
    if c = invalid then return
    p = Pal()
    active = m.top.focusPercent > 0.5 and m.top.listHasFocus
    isPlaying = (c.id <> "" and c.id = m.global.playingId)
    isFav = (m.global.favIds[c.id] = true)

    m.num.text = c.ShortDescriptionLine1
    SetText(m.name, c.title)
    SetText(m.now, c.ShortDescriptionLine2)

    ' right-hand marks, laid out from the right edge
    right = 600
    m.playing.visible = isPlaying
    if isPlaying
        w = 18 + TextWidth(m.playText)
        right = right - w
        m.playing.translation = [right, 0]
        right = right - 16
    end if
    m.star.visible = isFav
    if isFav
        right = right - 26
        m.star.translation = [right, 31]
        right = right - 14
    end if
    m.name.width = right - 196
    m.now.width = right - 196

    if active
        m.fill.visible = true
        m.fill.blendColor = p.w100
        m.num.color = p.ink60
        m.tile.blendColor = p.ink08
        m.abbr.color = p.ink60
        m.name.color = p.ink
        m.now.color = p.ink60
        m.star.blendColor = p.ink
        m.playText.color = p.ink
    else
        m.fill.visible = (m.top.focusPercent > 0.5)   ' faint footprint when the list isn't focused
        m.fill.blendColor = p.w06
        m.num.color = p.w35
        m.tile.blendColor = p.w08
        m.abbr.color = p.w60
        m.name.color = p.w85
        m.now.color = p.w35
        m.star.blendColor = p.w85
        m.playText.color = p.w85
    end if
end sub
