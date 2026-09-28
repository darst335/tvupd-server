#!/bin/sh
# 通过 adb 把盒子端装进 /system（要求：盒子已 root、网络调试已开）
# 用法:  sh install-to-box.sh <盒子IP> [adb端口，默认30016]
#
# 装之前先改 box/system/etc/tv-updater.conf 里的 MANIFEST_URL 指向你的服务器。
set -e
IP=${1:?用法: sh install-to-box.sh <盒子IP> [端口]}
PORT=${2:-30016}
BASE=$(cd "$(dirname "$0")" && pwd)
ADB=${ADB:-adb}

echo "== 连接 $IP:$PORT =="
$ADB connect "$IP:$PORT"
S="$IP:$PORT"
$ADB -s "$S" root >/dev/null 2>&1 || true
sleep 1

echo "== 写入 /system =="
$ADB -s "$S" shell "mount -o remount,rw /system"
$ADB -s "$S" push "$BASE/system/bin/tv-updater"  /system/bin/tv-updater
$ADB -s "$S" push "$BASE/system/bin/tv-maint"    /system/bin/tv-maint
$ADB -s "$S" push "$BASE/system/bin/tv-oemctl"   /system/bin/tv-oemctl
$ADB -s "$S" push "$BASE/system/etc/install-recovery.sh"   /system/etc/install-recovery.sh
$ADB -s "$S" push "$BASE/system/etc/install-recovery-2.sh" /system/etc/install-recovery-2.sh
$ADB -s "$S" push "$BASE/system/etc/tv-updater.conf"       /system/etc/tv-updater.conf
$ADB -s "$S" shell "chmod 755 /system/bin/tv-updater /system/bin/tv-maint /system/bin/tv-oemctl /system/etc/install-recovery.sh /system/etc/install-recovery-2.sh; chmod 644 /system/etc/tv-updater.conf; chown 0.0 /system/bin/tv-* /system/etc/install-recovery*.sh /system/etc/tv-updater.conf"

# 免授权 adb 公钥（可选）：把自己的 adbkey.pub 放到本目录 tv-adbkey，会自动装进盒子
if [ -f "$BASE/tv-adbkey" ]; then
    $ADB -s "$S" shell "mkdir -p /data/misc/adb"
    $ADB -s "$S" push "$BASE/tv-adbkey" /data/misc/adb/adb_keys
    $ADB -s "$S" shell "chmod 600 /data/misc/adb/adb_keys; chown 1000.2000 /data/misc/adb/adb_keys"
fi

echo "== 立即跑一轮（拉清单 + 收敛）=="
$ADB -s "$S" shell "/system/bin/tv-updater once; echo EXIT=\$?"
echo
echo "完成。盒子已纳入管理：开机自启（install-recovery），每 ${INTERVAL:-600} 秒自查一次。"
echo "验证: 控制台总览应出现这台盒子；或在盒子上看 /data/local/tv-updater/boot.log"
