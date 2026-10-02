# -*- coding: utf-8 -*-
"""把 tv-* 远程控制系统写入固件目录 update/system/，并登记 filesystem_config.txt。
可重复执行（幂等）。

用法（不写死任何机器的路径，全部走命令行参数）:
    python write_fw.py --fw <固件解包目录/update> --kit <tvkit 目录>

  --fw  指到固件解包出来的 update/ 目录（下面要有 META/filesystem_config.txt）
  --kit 指到待写入的 tvkit 目录（下面要有 tv-updater / tv-maint / … / tv-adbkey）
"""
import argparse, os, shutil

ap = argparse.ArgumentParser(description="把 tv-* 组件写入固件树并登记 filesystem_config.txt")
ap.add_argument("--fw", required=True, help="固件解包目录（update/，内含 META/filesystem_config.txt）")
ap.add_argument("--kit", required=True, help="待写入组件所在目录（tvkit）")
a = ap.parse_args()

FW = a.fw
KIT = a.kit

FILES = [
    ("tv-updater",            "system/bin/tv-updater",              "0 2000 755"),
    ("tv-maint",              "system/bin/tv-maint",                "0 2000 755"),
    ("tv-oemctl",             "system/bin/tv-oemctl",               "0 2000 755"),
    ("install-recovery.sh",   "system/etc/install-recovery.sh",     "0 0 755"),
    ("install-recovery-2.sh", "system/etc/install-recovery-2.sh",   "0 0 755"),
    ("tv-updater.conf",       "system/etc/tv-updater.conf",         "0 0 644"),
    ("tv-adbkey",             "system/etc/tv-adbkey",               "0 0 644"),
]

FC = os.path.join(FW, "META", "filesystem_config.txt")

# 1) 拷贝脚本文件（二进制拷贝，保持 LF）
for src, rel, mode in FILES:
    dst = os.path.join(FW, rel.replace("/", os.sep))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(os.path.join(KIT, src), dst)
    # 校验没有 CRLF
    data = open(dst, "rb").read()
    assert b"\r\n" not in data, f"{rel} 出现 CRLF！"
    print("copied", rel, len(data))

# 2) filesystem_config.txt 登记（幂等：已存在则替换 mode，否则插入到合适位置）
raw = open(FC, "r", encoding="utf-8", newline="").read()
lines = raw.replace("\r\n", "\n").split("\n")
have = {}
for i, l in enumerate(lines):
    if not l.strip():
        continue
    parts = l.split()
    if len(parts) >= 4:
        have[parts[0]] = i

changed = []
for src, rel, mode in FILES:
    entry = f"{rel} {mode}"
    if rel in have:
        lines[have[rel]] = entry
        changed.append(f"更新 {rel}")
    else:
        # 插到同目录下第一个条目之前（保持大致有序）
        d = os.path.dirname(rel)
        idx = None
        for i, l in enumerate(lines):
            if l.startswith(d + "/") or l == d:
                idx = i
        # 找到该目录下最后一个条目
        if idx is not None:
            j = idx
            while j + 1 < len(lines) and (lines[j + 1].startswith(d + "/") or lines[j + 1] == d):
                j += 1
            lines.insert(j + 1, entry)
        else:
            lines.append(entry)
        changed.append(f"新增 {rel}")

if not os.path.exists(FC + ".bak"):
    shutil.copyfile(FC, FC + ".bak")
    print("已备份 filesystem_config.txt -> .bak")

with open(FC, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))

print("filesystem_config.txt:", "; ".join(changed))
print("done")
