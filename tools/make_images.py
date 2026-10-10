# Generates simple placeholder icon/splash PNGs (dark bg + blue play triangle). No deps.
import zlib, struct, sys
def png(path, w, h):
    bg=(11,15,23); fg=(46,124,246)
    cx, cy, r = w/2, h/2, min(w, h)*0.28
    rows=[]
    for y in range(h):
        row=bytearray([0])
        for x in range(w):
            # right-pointing triangle centred on (cx, cy)
            dx, dy = x-(cx-r*0.6), abs(y-cy)
            inside = 0 <= dx <= r*1.5 and dy <= (r*1.5-dx)*0.62
            row += bytes(fg if inside else bg)
        rows.append(bytes(row))
    raw=b''.join(rows)
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    open(path,'wb').write(data)
out=sys.argv[1]
png(out+'/icon_hd.png',290,218); png(out+'/icon_fhd.png',540,405); png(out+'/splash_fhd.png',1920,1080)
