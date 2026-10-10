sub init()
    m.bar = m.top.FindNode("bar")
    m.star = m.top.FindNode("star")
    m.name = m.top.FindNode("name")
    m.count = m.top.FindNode("count")
    m.divider = m.top.FindNode("divider")
    m.content = invalid
end sub

sub onContent()
    if m.content <> invalid then m.content.UnobserveFieldScoped("ShortDescriptionLine1")
    m.content = m.top.itemContent
    if m.content <> invalid then m.content.ObserveFieldScoped("ShortDescriptionLine1", "render")
    render()
end sub

sub render()
    c = m.content
    if c = invalid then return
    p = Pal()
    isFav = (c.id = "fav")
    selected = m.top.focusPercent > 0.5
    active = selected and m.top.listHasFocus

    SetText(m.name, c.title)
    m.count.text = c.ShortDescriptionLine1
    m.divider.visible = isFav
    m.star.visible = isFav

    x = 0
    if selected then x = 20
    m.star.translation = [x, 18]
    if isFav then x = x + 40
    m.name.translation = [x, 0]
    m.name.width = 240 - x

    m.bar.visible = selected
    if active
        m.bar.color = p.w100
        m.name.color = p.w100
        m.count.color = p.w60
        m.star.blendColor = p.w100
    else if selected
        m.bar.color = p.w35
        m.name.color = p.w85
        m.count.color = p.w35
        m.star.blendColor = p.w85
    else
        m.name.color = p.w60
        m.count.color = p.w35
        m.star.blendColor = p.w60
    end if
end sub
