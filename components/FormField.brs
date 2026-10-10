sub init()
    m.fill = m.top.FindNode("fill")
    m.rule = m.top.FindNode("rule")
    m.lbl = m.top.FindNode("lbl")
    m.val = m.top.FindNode("val")
    render()
end sub

sub render()
    p = Pal()
    m.lbl.text = UCase(m.top.label)
    v = m.top.value
    empty = (v = "")
    if empty
        v = m.top.placeholder
    else if m.top.secure
        dots = ""
        for i = 1 to Len(v)
            dots = dots + "•"
        end for
        v = dots
    end if
    m.val.text = v

    if m.top.focused
        m.fill.visible = true
        m.fill.blendColor = p.w100
        m.rule.visible = false
        m.lbl.color = p.ink60
        if empty then m.val.color = p.ink60 else m.val.color = p.ink
    else
        m.fill.visible = false
        m.rule.visible = true
        m.rule.color = p.w15
        m.lbl.color = p.w35
        if empty then m.val.color = p.w35 else m.val.color = p.w85
    end if
end sub
