# -*- coding: utf-8 -*-
"""在原 cpio 基础上替换 init.rc，重建 ramdisk 并组装 boot.img。
保留原 cpio 的条目顺序 / mode / uid / gid / mtime（海思镜像对结构敏感，只改内容不改元数据）。

用法（不写死任何机器的路径，全部走命令行参数）:
    python pack_boot.py --boot <原boot.img> --cpio <原ramdisk.cpio> \
        --initrc <新init.rc> --out <boot_new.img> \
        [--page 16384] [--kernel-size 8617844] [--ramdisk-orig 414514]

  --kernel-size / --page 是机型相关的偏移参数（默认值取自 UNT401H / Hi3798MV310 的 4.4 固件），
  换机型务必按自己的 boot 头重算。
"""
import argparse, zlib, struct

ap = argparse.ArgumentParser(description="替换 init.rc 并重建 boot.img")
ap.add_argument("--boot", required=True, help="原始 boot.img")
ap.add_argument("--cpio", required=True, help="原始 ramdisk 的 cpio（未 gzip）")
ap.add_argument("--initrc", required=True, help="替换用的 init.rc")
ap.add_argument("--out", required=True, help="输出 boot_new.img")
ap.add_argument("--page", type=int, default=16384, help="boot 页大小（默认 16384）")
ap.add_argument("--kernel-size", type=int, default=8617844,
                help="内核段大小（默认 UNT401H 4.4 固件的 8617844）")
ap.add_argument("--ramdisk-orig", type=int, default=414514,
                help="原 ramdisk 的 gzip 大小（仅用于打印对比，不影响产出）")
a = ap.parse_args()

BOOT, CPIO, NEWINITRC, OUT = a.boot, a.cpio, a.initrc, a.out
PAGE = a.page
KERNEL_SIZE = a.kernel_size
RAMDISK_OFF = PAGE + ((KERNEL_SIZE + PAGE - 1) // PAGE) * PAGE

data = open(BOOT, 'rb').read()
orig = open(CPIO, 'rb').read()
newrc = open(NEWINITRC, 'rb').read()
print("orig cpio", len(orig), "new init.rc", len(newrc))

# ---------- 1) 解析原 cpio ----------
entries = []
pos = 0
while pos < len(orig) - 110:
    if orig[pos:pos+6] != b'070701':
        j = orig.find(b'070701', pos)
        if j < 0:
            break
        pos = j
        continue
    f = orig[pos+6:pos+6+13*8]
    vals = [int(f[k*8:(k+1)*8], 16) for k in range(13)]
    ino, mode, uid, gid, nlink, mtime, filesize = vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6]
    devmajor, devminor, rdevmajor, rdevminor, namesize, check = vals[7], vals[8], vals[9], vals[10], vals[11], vals[12]
    name = orig[pos+110:pos+110+namesize-1].decode('latin1')
    hdr_len = (110 + namesize + 3) & ~3
    dstart = pos + hdr_len
    content = orig[dstart:dstart+filesize]
    entries.append(dict(name=name, ino=ino, mode=mode, uid=uid, gid=gid, nlink=nlink,
                        mtime=mtime, devmajor=devmajor, devminor=devminor,
                        rdevmajor=rdevmajor, rdevminor=rdevminor, data=content))
    if name == 'TRAILER!!!':
        break
    pos = (dstart + filesize + 3) & ~3
print("entries", len(entries))

# ---------- 2) 替换 init.rc ----------
hit = 0
for e in entries:
    if e['name'] in ('init.rc', '/init.rc'):
        print("replace", e['name'], len(e['data']), "->", len(newrc))
        e['data'] = newrc
        hit += 1
assert hit == 1, f"init.rc 条目命中 {hit} 次，异常"

# ---------- 3) 重建 cpio ----------
def pad4(b):
    r = len(b) % 4
    return b + b'\0' * ((4 - r) % 4)

out = bytearray()
for e in entries:
    nm = e['name'].encode('latin1') + b'\0'
    fields = [e['ino'], e['mode'], e['uid'], e['gid'], e['nlink'], e['mtime'],
              len(e['data']), e['devmajor'], e['devminor'], e['rdevmajor'],
              e['rdevminor'], len(nm), 0]
    out += b'070701'
    for v in fields:
        out += ('%08X' % (v & 0xFFFFFFFF)).encode('ascii')
    out += nm
    out = bytearray(pad4(bytes(out)))
    out += e['data']
    out = bytearray(pad4(bytes(out)))
newcpio = bytes(out)
print("new cpio", len(newcpio))

# ---------- 4) gzip ----------
co = zlib.compressobj(9, zlib.DEFLATED, 31)   # 31 = gzip
gz = co.compress(newcpio) + co.flush()
print("gzip ramdisk", len(gz), "(orig", a.ramdisk_orig, ")")

# ---------- 5) 组装 boot.img ----------
hdr = bytearray(data[:PAGE])
struct.pack_into('<I', hdr, 16, len(gz))      # ramdisk_size
kernel = data[PAGE:PAGE + KERNEL_SIZE]
img = bytearray()
img += hdr
img += kernel
img = bytearray(bytes(img) + b'\0' * (((len(img) + PAGE - 1) // PAGE) * PAGE - len(img)))
img += gz
img += b'\0' * (((len(img) + PAGE - 1) // PAGE) * PAGE - len(img))
open(OUT, 'wb').write(bytes(img))
print("wrote", OUT, len(img), "(orig", len(data), ")")

# ---------- 6) 自校验 ----------
chk = open(OUT, 'rb').read()
assert chk[:8] == b'ANDROID!'
rs = struct.unpack('<I', chk[16:20])[0]
d = zlib.decompressobj(16 + zlib.MAX_WBITS)
c = d.decompress(chk[RAMDISK_OFF:RAMDISK_OFF + rs])
print("verify: ramdisk_size", rs, "decompressed", len(c))
idx = c.find(b'setprop persist.sys.debugenable 1')
print("verify: 新 init.rc 内容在 ramdisk 中:", idx >= 0)
assert idx >= 0
print("OK")
