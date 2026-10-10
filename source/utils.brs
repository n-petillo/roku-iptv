' Pure helpers shared by the render thread, tasks and tests.
' No SceneGraph nodes or network access in here.

' Prefilled on the login form; editable for other providers.
function DefaultServer() as string
    return "http://ipservz.net"
end function

' "my.host:8080/" -> "http://my.host:8080"
function NormalizeServer(s as string) as string
    s = s.Trim()
    if s = "" then return ""
    lower = LCase(s)
    if Left(lower, 7) <> "http://" and Left(lower, 8) <> "https://" then s = "http://" + s
    ' people often paste a full API or m3u link; keep only scheme://host[:port]
    for each marker in ["/player_api.php", "/get.php", "/xmltv.php"]
        idx = Instr(1, LCase(s), marker)
        if idx > 0 then s = Left(s, idx - 1)
    end for
    while Right(s, 1) = "/"
        s = Left(s, Len(s) - 1)
    end while
    sep = Instr(1, s, "://")
    if sep = 0 or sep + 3 > Len(s) then return ""   ' scheme only, no host
    return s
end function

function ApiUrl(creds as object, params as object) as string
    url = creds.server + "/player_api.php?username=" + creds.username.EncodeUriComponent() + "&password=" + creds.password.EncodeUriComponent()
    if params <> invalid
        for each k in params
            url = url + "&" + k + "=" + AnyToStr(params[k]).EncodeUriComponent()
        end for
    end if
    return url
end function

function StreamUrl(creds as object, streamId as string, ext as string) as string
    return creds.server + "/live/" + creds.username.EncodeUriComponent() + "/" + creds.password.EncodeUriComponent() + "/" + streamId + "." + ext
end function

function AnyToStr(v as dynamic) as string
    if v = invalid then return ""
    t = Type(v)
    if t = "roString" or t = "String" then return v
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v.ToStr()
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
        if v = Int(v) then return Int(v).ToStr()
        return Str(v).Trim()
    end if
    if t = "roBoolean" or t = "Boolean"
        if v then return "true"
        return "false"
    end if
    return ""
end function

function AnyToInt(v as dynamic) as integer
    s = AnyToStr(v)
    if s = "" then return 0
    return s.ToInt()
end function

function DecodeB64(s as dynamic) as string
    s = AnyToStr(s)
    if s = "" then return ""
    ba = CreateObject("roByteArray")
    ba.FromBase64String(s)
    out = ba.ToAsciiString()
    if out = "" then return s
    return out
end function

' Returns "" when the login response is OK, otherwise a user-facing error.
function LoginError(json as dynamic) as string
    if json = invalid or Type(json) <> "roAssociativeArray" then return "Server did not return a valid Xtream response."
    ui = json.user_info
    if ui = invalid then return "Server did not return a valid Xtream response."
    if AnyToInt(ui.auth) <> 1 then return "Wrong username or password."
    status = AnyToStr(ui.status)
    if status <> "" and LCase(status) <> "active" then return "Account status: " + status
    exp = AnyToInt(ui.exp_date)
    if exp > 0 and exp < NowSecs() then return "Account expired."
    return ""
end function

' get_short_epg -> array of {title, desc, start, ends} sorted by start, dropping ended programmes.
function ParseShortEpg(json as dynamic, now as integer) as object
    out = []
    if json = invalid or Type(json) <> "roAssociativeArray" then return out
    listings = json.epg_listings
    if listings = invalid or Type(listings) <> "roArray" then return out
    for each e in listings
        if Type(e) = "roAssociativeArray"
            start = AnyToInt(e.start_timestamp)
            ends = AnyToInt(e.stop_timestamp)
            if start > 0 and ends > now
                out.Push({ title: DecodeB64(e.title), desc: DecodeB64(e.description), start: start, ends: ends })
            end if
        end if
    end for
    out.SortBy("start")
    return out
end function

' Picks the stream extension from user_info.allowed_output_formats: m3u8 when allowed, else ts.
function PreferredExt(json as dynamic) as string
    if json = invalid or Type(json) <> "roAssociativeArray" or json.user_info = invalid then return "m3u8"
    formats = json.user_info.allowed_output_formats
    if formats = invalid or Type(formats) <> "roArray" or formats.Count() = 0 then return "m3u8"
    for each f in formats
        if AnyToStr(f) = "m3u8" then return "m3u8"
    end for
    for each f in formats
        if AnyToStr(f) = "ts" then return "ts"
    end for
    return "m3u8"
end function

function NowSecs() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

function FmtTime(secs as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(secs)
    dt.ToLocalTime()
    return Pad2(dt.GetHours()) + ":" + Pad2(dt.GetMinutes())
end function

function Pad2(n as integer) as string
    s = n.ToStr()
    if Len(s) < 2 then s = "0" + s
    return s
end function

function Progress(start as integer, ends as integer, now as integer) as float
    if ends <= start then return 0.0
    p = (now - start) / (ends - start)
    if p < 0 then return 0.0
    if p > 1 then return 1.0
    return p
end function

' "Atlas Nature HD" -> "AN"
function Abbrev(name as string) as string
    out = ""
    for each w in name.Trim().Split(" ")
        if w <> "" and Len(out) < 2 then out = out + UCase(Left(w, 1))
    end for
    return out
end function

function MinLeftText(secs as integer) as string
    mins = Int((secs + 59) / 60)
    if mins < 1 then mins = 1
    return mins.ToStr() + " min left"
end function

' Channel-row subtitle: "Coastlines · 34 min left"
function NowLine(p as dynamic, now as integer) as string
    if p = invalid then return ""
    return p.title + " · " + MinLeftText(p.ends - now)
end function

' "Thu 20:26"
function FmtClock(secs as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(secs)
    dt.ToLocalTime()
    return Left(dt.GetWeekday(), 3) + " " + Pad2(dt.GetHours()) + ":" + Pad2(dt.GetMinutes())
end function

' Favorites are an ordered array of {id, title, num, icon}.
function FavIndex(favs as object, id as string) as integer
    for i = 0 to favs.Count() - 1
        if favs[i].id = id then return i
    end for
    return -1
end function

' Adds the channel if missing, removes it if present. Returns true when it was added.
function FavToggle(favs as object, entry as object) as boolean
    idx = FavIndex(favs, entry.id)
    if idx >= 0
        favs.Delete(idx)
        return false
    end if
    favs.Push(entry)
    return true
end function

' True when the text has characters beyond Latin Extended-A/B (Arabic, Cyrillic, Greek, ...),
' which ABC Normal can't draw.
function HasNonLatin(s as string) as boolean
    for i = 1 to Len(s)
        c = Asc(Mid(s, i, 1))
        if c > &h24F and c <> &h2013 and c <> &h2014 and c <> &h2022 and c <> &h2026 and (c < &h2190 or c > &h2193) then return true
    end for
    return false
end function
