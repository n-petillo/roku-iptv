' Children are laid out left to right, 40px apart, vertically centred on a 72px row.
sub render()
    p = Pal()
    while m.top.GetChildCount() > 0
        m.top.RemoveChildIndex(0)
    end while
    if m.top.hints = invalid then return

    x = 0
    for each h in m.top.hints
        cap = m.top.CreateChild("Group")
        cap.translation = [x, 22]
        border = MkPoster(cap, "pkg:/images/r6_line.9.png", 0, 0, 0, 28, p.w35)
        if h.k = "pp"
            capW = 56
            MkPoster(cap, "pkg:/images/playpause.png", 10, 4, 36, 20, p.w60)
        else
            k = MkLabel(cap, h.k, 10, 0, 16, p.w60)
            k.height = 28
            k.vertAlign = "center"
            capW = TextWidth(k) + 20
        end if
        border.width = capW
        t = MkLabel(m.top, h.t, x + capW + 12, 0, 20, p.w60)
        t.height = 72
        t.vertAlign = "center"
        x = x + capW + 12 + TextWidth(t) + 40
    end for
end sub
