sub init()
    m.heading = m.top.FindNode("heading")
    m.message = m.top.FindNode("message")
    m.detail = m.top.FindNode("detail")
    m.detailBox = m.top.FindNode("detailBox")
    m.detailBorder = m.top.FindNode("detailBorder")
    m.retry = m.top.FindNode("retry")
    m.edit = m.top.FindNode("edit")
    m.idx = 0
    m.top.FindNode("hints").hints = [{ k: "← →", t: "Choose" }, { k: "OK", t: "Select" }, { k: "Back", t: "Exit" }]
    m.top.ObserveField("focusedChild", "onFocusChange")
    render()
end sub

sub onFocusChange()
    if m.top.IsInFocusChain() and not m.top.HasFocus() then m.top.SetFocus(true)
end sub

sub render()
    m.heading.text = m.top.heading
    m.message.text = m.top.message
    m.detail.text = m.top.detail
    m.detailBox.visible = (m.top.detail <> "")
    m.detailBorder.width = TextWidth(m.detail) + 48
    m.retry.focused = (m.idx = 0)
    m.edit.focused = (m.idx = 1)
    m.edit.translation = [96 + m.retry.width + 20, 720]
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "left" or key = "right"
        m.idx = 1 - m.idx
        render()
        return true
    else if key = "OK"
        if m.idx = 0 then m.top.action = "retry" else m.top.action = "edit"
        return true
    end if
    ' Back bubbles up to MainScene, which exits
    return false
end function
