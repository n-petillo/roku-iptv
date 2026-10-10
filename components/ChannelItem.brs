sub init()
    m.num = m.top.FindNode("num")
    m.logo = m.top.FindNode("logo")
    m.name = m.top.FindNode("name")
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.num.text = c.ShortDescriptionLine1
    m.name.text = c.title
    m.logo.uri = c.HDPosterUrl
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.name.color = "0xFFFFFFFF"
        m.num.color = "0xFFFFFFFF"
    else
        m.name.color = "0xD5DBE5FF"
        m.num.color = "0x9AA4B5FF"
    end if
end sub
