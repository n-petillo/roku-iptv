sub init()
    m.bg = m.top.FindNode("bg")
    m.lbl = m.top.FindNode("lbl")
end sub

sub render()
    p = Pal()
    m.lbl.text = m.top.text
    w = TextWidth(m.lbl) + 88
    m.bg.width = w
    m.top.width = w
    if m.top.focused
        m.bg.uri = "pkg:/images/pill.9.png"
        m.bg.blendColor = p.w100
        m.lbl.color = p.ink
    else
        m.bg.uri = "pkg:/images/pill_line.9.png"
        m.bg.blendColor = p.w60
        m.lbl.color = p.w100
    end if
end sub
