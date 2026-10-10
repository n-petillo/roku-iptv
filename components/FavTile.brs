sub init()
    for each id in ["ring", "abbr", "logo", "track", "bar", "num", "name", "now"]
        m[id] = m.top.FindNode(id)
    end for
    m.content = invalid
    m.logo.ObserveField("loadStatus", "onLogoStatus")
end sub

sub onContent()
    if m.content <> invalid
        m.content.UnobserveFieldScoped("ShortDescriptionLine2")
        m.content.UnobserveFieldScoped("prog")
    end if
    m.content = m.top.itemContent
    if m.content = invalid then return
    m.content.ObserveFieldScoped("ShortDescriptionLine2", "render")
    m.content.ObserveFieldScoped("prog", "render")
    m.abbr.text = Abbrev(m.content.title)
    m.logo.uri = m.content.HDPosterUrl
    onLogoStatus()
    render()
end sub

sub onLogoStatus()
    m.abbr.visible = (m.logo.uri = "" or m.logo.loadStatus <> "ready")
end sub

sub render()
    c = m.content
    if c = invalid then return
    p = Pal()
    active = m.top.focusPercent > 0.5 and m.top.gridHasFocus
    m.ring.visible = active

    m.num.text = c.ShortDescriptionLine1
    nameX = 0
    if m.num.text <> "" then nameX = TextWidth(m.num) + 14
    m.name.translation = [nameX, 214]
    m.name.width = 408 - nameX
    SetText(m.name, c.title)
    SetText(m.now, c.ShortDescriptionLine2)

    prog = 0.0
    if c.prog <> invalid then prog = c.prog
    m.track.visible = prog > 0
    m.bar.visible = prog > 0
    m.bar.width = Int(408 * prog)

    if active
        m.num.color = p.w60
        m.name.color = p.w100
        m.now.color = p.w60
        m.bar.color = p.w100
    else
        m.num.color = p.w35
        m.name.color = p.w85
        m.now.color = p.w35
        m.bar.color = p.w85
    end if
end sub
