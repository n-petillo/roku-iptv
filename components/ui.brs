' Shared look: Runway ink + white opacity ladder, one ember accent, ABC Normal.

function Pal() as object
    return {
        ink: "0x0C0C0CFF",
        w100: "0xFFFFFFFF", w85: "0xFFFFFFD9", w60: "0xFFFFFF99", w35: "0xFFFFFF59",
        w15: "0xFFFFFF26", w12: "0xFFFFFF1F", w10: "0xFFFFFF1A", w08: "0xFFFFFF14", w06: "0xFFFFFF0F",
        ink85: "0x0C0C0CD9", ink60: "0x0C0C0C99", ink08: "0x0C0C0C14",
        ember: "0xB35A45FF", emberLight: "0xD78A6AFF"
    }
end function

' weight: false = Normal (400), true = Regular (500, used for big numbers)
function Fnt(size as integer, medium = false as boolean) as object
    f = CreateObject("roSGNode", "Font")
    if medium then f.uri = "pkg:/fonts/ABCNormal-Regular.otf" else f.uri = "pkg:/fonts/ABCNormal-Normal.otf"
    f.size = size
    return f
end function

function MkLabel(parent as object, text as string, x as integer, y as integer, size as integer, color as string) as object
    l = parent.CreateChild("Label")
    l.font = Fnt(size)
    l.text = text
    l.color = color
    l.translation = [x, y]
    return l
end function

function MkPoster(parent as object, uri as string, x as integer, y as integer, w as integer, h as integer, color as string) as object
    p = parent.CreateChild("Poster")
    p.uri = uri
    p.translation = [x, y]
    p.width = w
    p.height = h
    p.blendColor = color
    return p
end function

' Width of a label's text; falls back to an estimate if the font isn't measured yet.
function TextWidth(l as object) as integer
    r = l.boundingRect()
    if r <> invalid and r.width > 0 then return Int(r.width)
    return Int(Len(l.text) * l.font.size * 0.55)
end function

' Sets label text, swapping to the Roku system font for scripts ABC Normal lacks
' (provider names are often Arabic/Cyrillic) and back again when a recycled row gets Latin text.
sub SetText(l as object, text as string)
    l.text = text
    if not l.HasField("abcSize")
        l.AddField("abcSize", "integer", false)
        l.AddField("abcMedium", "boolean", false)
        l.abcSize = l.font.size
        l.abcMedium = Instr(1, l.font.uri, "Regular") > 0
        l.AddField("sysFont", "boolean", false)
    end if
    want = HasNonLatin(text)
    if want = l.sysFont then return
    l.sysFont = want
    if want
        l.font = "font:MediumSystemFont"
        l.font.size = l.abcSize
    else
        l.font = Fnt(l.abcSize, l.abcMedium)
    end if
end sub
