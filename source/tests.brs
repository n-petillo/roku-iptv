' Minimal test runner for utils.brs.
' On device: make test   (output on the debug console, telnet <ip> 8085)
' Locally:   make unit   (runs under brs-engine)

sub RunTests()
    t = { pass: 0, fail: 0 }

    Eq(t, "normalize adds scheme", NormalizeServer("my.host:8080"), "http://my.host:8080")
    Eq(t, "normalize strips slash", NormalizeServer(" http://a.b:80/ "), "http://a.b:80")
    Eq(t, "normalize keeps https", NormalizeServer("https://a.b"), "https://a.b")
    Eq(t, "normalize strips api path", NormalizeServer("http://a.b:8080/player_api.php?username=x"), "http://a.b:8080")
    Eq(t, "normalize strips get.php", NormalizeServer("a.b/get.php?username=x&type=m3u"), "http://a.b")
    Eq(t, "normalize empty", NormalizeServer("  "), "")
    Eq(t, "normalize scheme only", NormalizeServer("http://"), "")
    Eq(t, "normalize scheme slash", NormalizeServer("http:///"), "")

    Eq(t, "ext default", PreferredExt({ user_info: {} }), "m3u8")
    Eq(t, "ext ts only", PreferredExt({ user_info: { allowed_output_formats: ["ts"] } }), "ts")
    Eq(t, "ext both", PreferredExt({ user_info: { allowed_output_formats: ["ts", "m3u8", "rtmp"] } }), "m3u8")
    Eq(t, "ext garbage", PreferredExt(invalid), "m3u8")

    creds = { server: "http://h:1", username: "u s", password: "p&w" }
    Eq(t, "api url", ApiUrl(creds, { action: "get_live_streams", category_id: 5 }), "http://h:1/player_api.php?username=u%20s&password=p%26w&action=get_live_streams&category_id=5")
    Eq(t, "api url no params", ApiUrl(creds, invalid), "http://h:1/player_api.php?username=u%20s&password=p%26w")
    Eq(t, "stream url", StreamUrl(creds, "42", "m3u8"), "http://h:1/live/u%20s/p%26w/42.m3u8")

    Eq(t, "anytostr int", AnyToStr(12), "12")
    Eq(t, "anytostr float int", AnyToStr(12.0), "12")
    Eq(t, "anytostr invalid", AnyToStr(invalid), "")
    Eq(t, "anytoint str", AnyToInt("1700000000"), 1700000000)
    Eq(t, "b64", DecodeB64("SGVsbG8gV29ybGQ="), "Hello World")
    Eq(t, "b64 empty", DecodeB64(invalid), "")

    Eq(t, "login ok", LoginError({ user_info: { auth: 1, status: "Active", exp_date: invalid } }), "")
    Eq(t, "login ok string auth", LoginError({ user_info: { auth: "1", status: "Active", exp_date: "4102444800" } }), "")
    Eq(t, "login bad auth", LoginError({ user_info: { auth: 0 } }), "Wrong username or password.")
    Eq(t, "login expired", LoginError({ user_info: { auth: 1, status: "Active", exp_date: "1000" } }), "Account expired.")
    Eq(t, "login disabled", LoginError({ user_info: { auth: 1, status: "Disabled" } }), "Account status: Disabled")
    Eq(t, "login garbage", LoginError(invalid), "Server did not return a valid Xtream response.")

    json = { epg_listings: [
        { title: "QiBTaG93", description: "", start_timestamp: "2000", stop_timestamp: "3000" },
        { title: "T2xk", description: "", start_timestamp: "500", stop_timestamp: "900" },
        { title: "QSBTaG93", description: "RGVzYw==", start_timestamp: "1000", stop_timestamp: "2000" }
    ] }
    epg = ParseShortEpg(json, 1500)
    Eq(t, "epg drops ended", epg.Count(), 2)
    Eq(t, "epg sorted", epg[0].title, "A Show")
    Eq(t, "epg desc", epg[0].desc, "Desc")
    Eq(t, "epg second", epg[1].title, "B Show")
    Eq(t, "epg garbage", ParseShortEpg(invalid, 0).Count(), 0)
    Eq(t, "epg no listings", ParseShortEpg({ epg_listings: invalid }, 0).Count(), 0)

    Eq(t, "progress mid", Progress(1000, 2000, 1500), 0.5)
    Eq(t, "progress clamp low", Progress(1000, 2000, 0), 0.0)
    Eq(t, "progress clamp high", Progress(1000, 2000, 9999), 1.0)
    Eq(t, "pad2", Pad2(7), "07")
    Eq(t, "fmttime shape", Len(FmtTime(1700000000)), 5)

    print "TESTS DONE: "; t.pass; " passed, "; t.fail; " failed"
end sub

sub Eq(t as object, name as string, actual as dynamic, expected as dynamic)
    if actual = expected
        t.pass = t.pass + 1
    else
        t.fail = t.fail + 1
        print "FAIL "; name; ": got ["; actual; "] expected ["; expected; "]"
    end if
end sub
