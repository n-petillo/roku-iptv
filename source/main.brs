sub Main(args as dynamic)
    if args <> invalid and args.runTests = "true"
        RunTests()
        return
    end if

    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.Show()
    scene.ObserveField("exitApp", port)

    while true
        msg = wait(0, port)
        t = Type(msg)
        if t = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        else if t = "roSGNodeEvent"
            if msg.GetField() = "exitApp" and msg.GetData() = true then return
        end if
    end while
end sub
