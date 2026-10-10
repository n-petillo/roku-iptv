sub init()
    m.rows = [m.top.FindNode("fServer"), m.top.FindNode("fUser"), m.top.FindNode("fPass"), m.top.FindNode("signIn")]
    m.fields = ["server", "username", "password"]
    m.status = m.top.FindNode("status")
    m.savedNote = m.top.FindNode("savedNote")
    m.values = { server: DefaultServer(), username: "", password: "" }
    m.idx = 1   ' server is prefilled, start on Username
    m.busy = false
    m.auto = false
    m.top.FindNode("version").text = "v" + CreateObject("roAppInfo").GetVersion()
    m.top.ObserveField("creds", "onCreds")
    m.top.ObserveField("focusedChild", "onFocusChange")
    render()
end sub

sub onFocusChange()
    ' keep key events on this screen (rows are drawn, not focusable lists)
    if m.top.IsInFocusChain() and not m.top.HasFocus() and m.dialog = invalid then m.top.SetFocus(true)
end sub

sub onCreds()
    c = m.top.creds
    if c = invalid then return
    m.values = { server: AnyToStr(c.server), username: AnyToStr(c.username), password: AnyToStr(c.password) }
    if m.values.server = "" then m.values.server = DefaultServer()
    ' land on the first empty field, else on Sign in
    m.idx = 3
    for i = 2 to 0 step -1
        if m.values[m.fields[i]] = "" then m.idx = i
    end for
    render()
end sub

sub onAutoLogin()
    if m.top.autoLogin
        m.auto = true
        doLogin()
    end if
end sub

sub render()
    for i = 0 to 2
        m.rows[i].value = m.values[m.fields[i]]
        m.rows[i].focused = (m.idx = i)
    end for
    btn = m.rows[3]
    btn.focused = (m.idx = 3)
    if m.busy then btn.text = "Signing in…" else btn.text = "Sign in"
    m.savedNote.translation = [660 + btn.width + 28, 720]
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or m.busy then return false
    if key = "up"
        if m.idx > 0 then m.idx = m.idx - 1
        render()
        return true
    else if key = "down"
        if m.idx < 3 then m.idx = m.idx + 1
        render()
        return true
    else if key = "OK"
        if m.idx < 3 then openKeyboard(m.fields[m.idx]) else doLogin()
        return true
    end if
    return false
end function

sub openKeyboard(field as string)
    titles = { server: "Server URL", username: "Username", password: "Password" }
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = titles[field]
    dlg.buttons = ["OK", "Cancel"]
    dlg.text = m.values[field]
    if field = "server"
        dlg.message = ["Include the port and http:// or https://"]
        if dlg.text = "" then dlg.text = DefaultServer()
    end if
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
        if m.idx < 3 then m.idx = m.idx + 1   ' advance to the next field
        render()
    end if
    dlg.close = true
end sub

sub onKeyboardClosed()
    m.dialog = invalid
    m.top.SetFocus(true)
end sub

sub showStatus(text as string, isError as boolean)
    p = Pal()
    if isError then m.status.color = p.emberLight else m.status.color = p.w60
    m.status.text = text
end sub

sub doLogin()
    creds = { server: NormalizeServer(m.values.server), username: m.values.username.Trim(), password: m.values.password }
    if creds.server = "" or creds.username = "" or creds.password = ""
        m.auto = false
        showStatus("Enter server, username and password.", true)
        return
    end if
    m.busy = true
    showStatus("Connecting to " + creds.server + " …", false)
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
    wasAuto = m.auto
    m.auto = false
    if res.ok
        showStatus("", false)
        m.pending.ext = res.data.ext
        m.top.loggedIn = m.pending
        return
    end if
    if wasAuto and res.netError = true
        m.top.autoFailed = { error: res.error, server: m.pending.server }
    end if
    showStatus(res.error, true)
    m.idx = 3
    render()
end sub
