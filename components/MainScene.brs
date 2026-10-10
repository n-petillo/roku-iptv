sub init()
    ' shared with list items so rows can show PLAYING / favorite marks without per-node fields
    m.global.AddFields({ playingId: "", favIds: {} })
    m.screen = invalid
    creds = loadCreds()
    showLogin(creds, hasPassword(creds))
end sub

sub showLogin(creds as dynamic, autoLogin as boolean)
    replaceScreen(CreateObject("roSGNode", "LoginScreen"))
    if creds <> invalid then m.screen.creds = creds
    m.screen.ObserveField("loggedIn", "onLoggedIn")
    m.screen.ObserveField("autoFailed", "onAutoFailed")
    if autoLogin then m.screen.autoLogin = true
end sub

sub onLoggedIn()
    creds = m.screen.loggedIn
    saveCreds(creds)
    showLive(creds)
end sub

sub showLive(creds as object)
    live = CreateObject("roSGNode", "LiveScreen")
    replaceScreen(live)
    live.ObserveField("logout", "onLogout")
    live.ObserveField("exitApp", "onExitApp")
    live.ObserveField("fatal", "onLiveFatal")
    live.creds = creds
end sub

' Saved login couldn't reach the server: show 1h instead of dumping the user on the form.
sub onAutoFailed()
    f = m.screen.autoFailed
    showError("Cannot reach server", f.server)
end sub

sub onLiveFatal()
    f = m.screen.fatal
    c = loadCreds()
    server = ""
    if c <> invalid then server = c.server
    showError(f.heading, server)
    if f.message <> invalid then m.screen.message = f.message
end sub

sub showError(heading as string, server as string)
    err = CreateObject("roSGNode", "ErrorScreen")
    replaceScreen(err)
    err.heading = heading
    err.detail = server
    err.ObserveField("action", "onErrorAction")
end sub

sub onErrorAction()
    creds = loadCreds()
    if m.screen.action = "retry" and hasPassword(creds)
        showLogin(creds, true)
    else
        showLogin(creds, false)
    end if
end sub

sub onLogout()
    ' forget the password so the next launch doesn't auto-login; keep server/username prefilled
    creds = loadCreds()
    if creds <> invalid
        creds.password = ""
        saveCreds(creds)
    end if
    m.global.playingId = ""
    showLogin(creds, false)
end sub

sub onExitApp()
    m.top.exitApp = true
end sub

sub replaceScreen(node as object)
    if m.screen <> invalid then m.top.RemoveChild(m.screen)
    m.screen = node
    m.top.AppendChild(node)
    node.SetFocus(true)
end sub

function loadCreds() as dynamic
    sec = CreateObject("roRegistrySection", "iptv")
    if not sec.Exists("creds") then return invalid
    c = ParseJson(sec.Read("creds"))
    if c = invalid or c.server = invalid or c.username = invalid or c.password = invalid then return invalid
    return c
end function

function hasPassword(c as dynamic) as boolean
    return c <> invalid and c.password <> ""
end function

sub saveCreds(creds as object)
    sec = CreateObject("roRegistrySection", "iptv")
    sec.Write("creds", FormatJson(creds))
    sec.Flush()
end sub
