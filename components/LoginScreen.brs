sub init()
    m.form = m.top.FindNode("form")
    m.status = m.top.FindNode("status")
    m.values = { server: "", username: "", password: "" }
    m.fields = ["server", "username", "password"]
    m.busy = false
    m.form.ObserveField("itemSelected", "onItemSelected")
    m.top.ObserveField("creds", "onCreds")
    m.top.ObserveField("focusedChild", "onFocusChange")
    render()
end sub

sub onFocusChange()
    if m.top.HasFocus() then m.form.SetFocus(true)
end sub

sub onCreds()
    c = m.top.creds
    if c = invalid then return
    m.values = { server: AnyToStr(c.server), username: AnyToStr(c.username), password: AnyToStr(c.password) }
    render()
end sub

sub onAutoLogin()
    if m.top.autoLogin then doLogin()
end sub

sub render()
    pw = ""
    for i = 1 to Len(m.values.password)
        pw = pw + "*"
    end for
    content = CreateObject("roSGNode", "ContentNode")
    addItem(content, "Server:  " + orHint(m.values.server, "http://host:port"))
    addItem(content, "Username:  " + orHint(m.values.username, ""))
    addItem(content, "Password:  " + orHint(pw, ""))
    if m.busy
        addItem(content, "Signing in...")
    else
        addItem(content, "[ Sign in ]")
    end if
    focused = m.form.itemFocused
    m.form.content = content
    if focused > 0 then m.form.jumpToItem = focused
end sub

function orHint(v as string, hint as string) as string
    if v <> "" then return v
    return hint
end function

sub addItem(parent as object, text as string)
    n = parent.CreateChild("ContentNode")
    n.title = text
end sub

sub onItemSelected()
    if m.busy then return
    idx = m.form.itemSelected
    if idx < 3
        openKeyboard(m.fields[idx])
    else
        doLogin()
    end if
end sub

sub openKeyboard(field as string)
    titles = { server: "Server URL", username: "Username", password: "Password" }
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = titles[field]
    dlg.buttons = ["OK", "Cancel"]
    dlg.text = m.values[field]
    if field = "server" and dlg.text = "" then dlg.text = "http://"
    if field = "password"
        dlg.keyboardDomain = "password"
        if dlg.textEditBox <> invalid then dlg.textEditBox.secureMode = true
    end if
    dlg.ObserveField("buttonSelected", "onKeyboardButton")
    dlg.ObserveField("wasClosed", "onKeyboardClosed")
    m.editing = field
    m.dialog = dlg
    m.top.GetScene().dialog = dlg
end sub

sub onKeyboardButton()
    dlg = m.dialog
    if dlg.buttonSelected = 0
        v = dlg.text.Trim()
        if m.editing = "server" then v = NormalizeServer(v)
        m.values[m.editing] = v
        render()
    end if
    dlg.close = true
end sub

sub onKeyboardClosed()
    m.dialog = invalid
    m.form.SetFocus(true)
end sub

sub doLogin()
    creds = { server: NormalizeServer(m.values.server), username: m.values.username.Trim(), password: m.values.password }
    if creds.server = "" or creds.username = "" or creds.password = ""
        m.status.color = "0xFF6B6BFF"
        m.status.text = "Enter server, username and password."
        return
    end if
    m.busy = true
    m.status.color = "0x9AA4B5FF"
    m.status.text = "Connecting to " + creds.server + " ..."
    render()
    m.pending = creds
    m.task = CreateObject("roSGNode", "ApiTask")
    m.task.ObserveField("result", "onLoginResult")
    m.task.request = { kind: "login", url: ApiUrl(creds, invalid), ctx: {} }
    m.task.control = "RUN"
end sub

sub onLoginResult()
    res = m.task.result
    m.task = invalid
    m.busy = false
    if res.ok
        m.status.text = ""
        m.pending.ext = res.data.ext
        m.top.loggedIn = m.pending
        return
    end if
    m.status.color = "0xFF6B6BFF"
    m.status.text = res.error
    render()
    m.form.jumpToItem = 3
    m.form.SetFocus(true)
end sub
