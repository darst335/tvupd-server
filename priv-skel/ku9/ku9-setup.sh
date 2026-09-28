#!/system/bin/sh
# 酷9 泉州台一键部署（由 tv-updater 的 sh 指令拉取执行，root 环境）
# 流程：预置目录与三件套配置 → pm clear 复位"首次运行"状态 → 启动酷9 自动加载预置订阅
# 说明：APK 本体由方案的 install 行负责安装；本脚本只负责配置文件与首次运行引导。
SRV="http://your.domain:8083"          # 分发服务器（含端口）
PKG="com.player.ku9lite"                     # 酷9 lite 包名
BASE="/sdcard/酷9"

BB=""
for c in /system/bin/busybox /system/xbin/busybox /system/bin/busybox-armv7l busybox; do
    [ -x "$c" ] && { BB="$c"; break; }
done
command -v busybox >/dev/null 2>&1 && BB=busybox
b() { if [ -n "$BB" ]; then $BB "$@"; else "$@"; fi; }

# ---- DNS 兼容层（同 tv-updater：系统 ping 解析 + IP/Host 头下载，绕开 busybox getaddrinfo 缺陷）----
DNSCACHE=/data/local/tmp/ku9dns
resolve_host() {
    h=$1
    case "$h" in *[!0-9.]*) ;; *) return 1 ;; esac
    b mkdir -p "$DNSCACHE" 2>/dev/null
    C="$DNSCACHE/$h"
    now=$(b date +%s)
    if [ -s "$C" ]; then
        t=$(b cut -d' ' -f1 "$C" 2>/dev/null)
        cip=$(b cut -d' ' -f2 "$C" 2>/dev/null)
        if [ -n "$t" ] && [ -n "$cip" ] && [ $((now - t)) -lt 600 ]; then
            echo "$cip"; return 0
        fi
    fi
    ip=$(ping -c 1 -W 2 "$h" 2>/dev/null | b grep -o '([0-9.]*)' | b sed -n 's/[()]//g;1p')
    [ -n "$ip" ] || return 1
    echo "$now $ip" > "$C"
    echo "$ip"; return 0
}

dl() { # $1=url $2=out
    case "$1" in http://*) rest=${1#http://} ;; *) return 1 ;; esac
    hp=${rest%%/*}; host=${hp%%:*}; port=${hp#"$host"}; path=${rest#"$hp"}
    case "$host" in
        *[!0-9.]*)
            ip=$(resolve_host "$host") || return 1
            b wget -q -T 30 -O "$2" --header "Host: $host" "http://$ip$port$path"
            ;;
        *) b wget -q -T 30 -O "$2" "$1" ;;
    esac
}

SN=$(getprop ro.serialno 2>/dev/null)
[ -n "$SN" ] || { echo "ku9-setup: 取不到序列号，无法授权"; exit 1; }

KU9_POS=0                                    # 酷9 放在首页快捷第几位（0=第一位）
KU9_ALIAS="酷9影视"

# 1) 预置目录（大小写各一份，兼容不同固件存储层的大小写行为）
for d in js JS logo Logo configuration Configuration; do b mkdir -p "$BASE/$d"; done

# 2) 拉取配置三件套（quanzhou.js / epg_data.json 走静态文件；
#    Configuration.json 由服务器按序列号生成，内含该盒专属订阅地址）
dl "$SRV/ku9/quanzhou.js"   "$BASE/js/quanzhou.js" \
    && b cp "$BASE/js/quanzhou.js" "$BASE/JS/quanzhou.js"
dl "$SRV/ku9/epg_data.json" "$BASE/logo/epg_data.json" \
    && b cp "$BASE/logo/epg_data.json" "$BASE/Logo/epg_data.json"
dl "$SRV/cgi-bin/admin?op=ku9cfg&sn=$SN" "$BASE/configuration/Configuration.json" \
    && b cp "$BASE/configuration/Configuration.json" "$BASE/Configuration/Configuration.json"

# 3) 校验关键文件存在且含预置订阅字段
ok=1
[ -s "$BASE/js/quanzhou.js" ]                   || ok=0
[ -s "$BASE/logo/epg_data.json" ]               || ok=0
grep -q "LIVE_URLS" "$BASE/configuration/Configuration.json" 2>/dev/null || ok=0
if [ "$ok" != "1" ]; then
    echo "ku9-setup: 配置文件下载/校验失败（sn=$SN，检查服务器授权名单）"
    exit 1
fi

# 4) 复位到"首次运行"状态——Configuration.json 的预置订阅只在首启/清数据后生效
pm clear "$PKG" >/dev/null 2>&1

# 4.5) 当贝桌面首页快捷图标（调控制台 op=scset 按参数生成的注入脚本，逻辑集中一份维护；
#      脚本自动适配多版本当贝 / 探测 Shortcut 表 / 上报结果到 launcher.log）
dbsc=/data/local/tmp/dbsc_$$
if dl "$SRV/cgi-bin/admin?op=scset&pos=$KU9_POS&pkg=$PKG&alias=$KU9_ALIAS" "$dbsc" && [ -s "$dbsc" ]; then
    sh "$dbsc"
    b rm -f "$dbsc"
else
    echo "ku9-setup: 快捷图标注入脚本拉取失败（不影响直播）"
fi

# 5) 启动酷9，自动加载预置订阅（客户开机即可看，无需任何遥控器操作）
monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "ku9-setup: 部署完成 sn=$SN"
