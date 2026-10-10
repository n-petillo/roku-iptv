sub init()
    m.top.functionName = "runTask"
end sub

sub runTask()
    req = m.top.request
    res = { kind: req.kind, ctx: req.ctx, ok: false, error: "", netError: false, data: invalid }

    timeout = 20000
    if req.timeoutMs <> invalid then timeout = req.timeoutMs
    body = httpGet(req.url, timeout, res)
    if body = invalid
        m.top.result = res
        return
    end if

    json = ParseJson(body)
    if json = invalid
        res.error = "Server returned an unexpected response."
        m.top.result = res
        return
    end if

    if req.kind = "login"
        res.error = LoginError(json)
        res.ok = (res.error = "")
        res.data = { ext: PreferredExt(json) }
    else if req.kind = "categories"
        m.top.content = buildCategories(json)
        res.ok = true
    else if req.kind = "streams"
        m.top.content = buildStreams(json)
        res.ok = true
    else if req.kind = "epg"
        res.data = ParseShortEpg(json, NowSecs())
        res.ok = true
    end if
    m.top.result = res
end sub

function httpGet(url as string, timeoutMs as integer, res as object) as dynamic
    port = CreateObject("roMessagePort")
    ut = CreateObject("roUrlTransfer")
    ut.SetMessagePort(port)
    ut.SetUrl(url)
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.EnableEncodings(true)
    ut.RetainBodyOnError(true)
    ut.AddHeader("User-Agent", "Mozilla/5.0 (Roku) FedSmokerTV/1.1")

    if not ut.AsyncGetToString()
        res.error = "Could not start request."
        return invalid
    end if
    msg = wait(timeoutMs, port)
    if msg = invalid
        ut.AsyncCancel()
        res.error = "Server timed out."
        res.netError = true
        return invalid
    end if
    code = msg.GetResponseCode()
    if code <> 200
        if code < 0
            res.error = "Cannot reach server (" + msg.GetFailureReason() + ")."
            res.netError = true
        else if code = 401 or code = 403
            res.error = "Wrong username or password."
        else
            res.error = "Server error (HTTP " + code.ToStr() + ")."
        end if
        return invalid
    end if
    return msg.GetString()
end function

function buildCategories(json as dynamic) as object
    root = CreateObject("roSGNode", "ContentNode")
    if Type(json) = "roArray"
        for each c in json
            if Type(c) = "roAssociativeArray"
                n = root.CreateChild("ContentNode")
                n.id = AnyToStr(c.category_id)
                n.title = AnyToStr(c.category_name)
            end if
        end for
    end if
    ' LiveScreen adds the pinned Favorites and All channels entries
    return root
end function

' ContentNode fields used: id = stream_id, title = name,
' HDPosterUrl = logo, ShortDescriptionLine1 = channel number.
function buildStreams(json as dynamic) as object
    root = CreateObject("roSGNode", "ContentNode")
    if Type(json) = "roArray"
        for each s in json
            if Type(s) = "roAssociativeArray"
                n = root.CreateChild("ContentNode")
                n.id = AnyToStr(s.stream_id)
                n.title = AnyToStr(s.name)
                n.HDPosterUrl = AnyToStr(s.stream_icon)
                n.ShortDescriptionLine1 = AnyToStr(s.num)
            end if
        end for
    end if
    return root
end function
