#!/system/bin/sh
# 当贝桌面首页快捷图标注入（由控制台 op=scset 按参数生成，勿手改）
# 适配多版本当贝：com.dangbei1.tvlauncher（老版 Shortcut 表）/ com.dangbei.tvlauncher（8.x）
# 流程：探测桌面包名+版本 → 扫描 databases 下含 Shortcut 表的库 → force-stop →
#       备份 → INSERT OR REPLACE（完整列，失败降级两列）→ 重启桌面 → devrep 上报结果
# 幂等可重复执行；失败不影响其他功能
SRV="@SRV@"
POS=@POS@
SPKG="@PKG@"
SALIAS="@ALIAS@"

# 精简 toolbox 固件（如 M301H_1ZN9_GD50）缺 head/tr/printf → 全部外部命令走 busybox
PATH=/system/bin:/system/xbin:$PATH
export PATH

BB=""
for c in /system/bin/busybox /system/xbin/busybox /system/bin/busybox-armv7l busybox; do
    [ -x "$c" ] && { BB="$c"; break; }
done
command -v busybox >/dev/null 2>&1 && BB=busybox
b() { if [ -n "$BB" ]; then $BB "$@"; else "$@"; fi; }

# ---- DNS 兼容层（同 tv-updater：系统 ping 解析 + IP/Host 头）----
DNSCACHE=/data/local/tmp/dbscdns
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
dpost() { # $1=完整URL，失败静默
    case "$1" in http://*) rest=${1#http://} ;; *) return ;; esac
    hp=${rest%%/*}; host=${hp%%:*}; port=${hp#"$host"}; path=/${rest#"$hp"}
    case "$host" in
        *[!0-9.]*)
            ip=$(resolve_host "$host") || return
            b wget -q -T 15 -O /dev/null --header "Host: $host" "http://$ip$port$path"
            ;;
        *) b wget -q -T 15 -O /dev/null "http://$host$port$path" ;;
    esac
}

SN=$(getprop ro.serialno 2>/dev/null)
[ -n "$SN" ] || SN="unknown"

SQLT=""
for s in /system/xbin/sqlite3 /system/bin/sqlite3 /data/local/tmp/sqlite3; do
    [ -x "$s" ] && { SQLT="$s"; break; }
done

LR=""; LPKG=""; LVER=""; DFILE=""; INFO=""
if [ -z "$SQLT" ]; then
    LR="nosqlite"
else
    for DP in com.dangbei1.tvlauncher com.dangbei.tvlauncher com.dangbei.tv.launcher; do
        # 部分固件 pm path 对不存在的包也返回 0（空输出）→ 必须看输出内容而不是退出码
        PP=$(pm path "$DP" 2>/dev/null | b grep -c package:)
        [ "$PP" -ge 1 ] 2>/dev/null || continue
        LPKG="$DP"
        LVER=$(dumpsys package "$DP" 2>/dev/null | b grep versionName | b head -n 1 | b sed 's/.*=//' | b tr -cd 'A-Za-z0-9._-')
        for DB in /data/data/$DP/databases/*.db; do
            [ -f "$DB" ] || continue
            T=$(echo "SELECT name FROM sqlite_master WHERE type='table' AND name='Shortcut';" | $SQLT "$DB" 2>/dev/null)
            case "$T" in *Shortcut*) DFILE="$DB"; break ;; esac
        done
        [ -n "$DFILE" ] && break
    done
    if [ -z "$LPKG" ]; then
        LR="nolauncher"
    elif [ -z "$DFILE" ]; then
        LR="nodb"
        for DB in /data/data/$LPKG/databases/*.db; do
            [ -f "$DB" ] || continue
            INFO="$INFO${DB##*/},"
        done
        INFO=$(b printf '%s' "$INFO" | b tr -cd 'A-Za-z0-9.,' | b cut -c 1-100)
    else
        SCHEMA=$(echo "SELECT sql FROM sqlite_master WHERE name='Shortcut';" | $SQLT "$DFILE" 2>/dev/null | b tr -d '\n\r')
        case "$SCHEMA" in
            *packageName*)
                am force-stop "$LPKG" >/dev/null 2>&1
                b cp "$DFILE" "$DFILE.bak" 2>/dev/null
                if echo "INSERT OR REPLACE INTO Shortcut (\"index\",folderId,packageName,appAlias) VALUES($POS,NULL,'$SPKG','$SALIAS');" | $SQLT "$DFILE" >/dev/null 2>&1; then
                    LR="ok"
                else
                    if echo "INSERT OR REPLACE INTO Shortcut (\"index\",packageName) VALUES($POS,'$SPKG');" | $SQLT "$DFILE" >/dev/null 2>&1; then
                        LR="fb"
                    else
                        LR="fail"
                    fi
                fi
                INFO=$(b printf '%s' "$SCHEMA" | b tr -cd 'A-Za-z0-9_,()' | b cut -c 1-100)
                b monkey -p "$LPKG" -c android.intent.category.HOME 1 >/dev/null 2>&1
                ;;
            *) LR="schema"
               INFO=$(b printf '%s' "$SCHEMA" | b tr -cd 'A-Za-z0-9_,()' | b cut -c 1-100) ;;
        esac
    fi
fi

dpost "$SRV/cgi-bin/admin?op=devrep&sn=$SN&lp=$LPKG&lv=$LVER&lr=$LR&cols=$INFO"
echo "dbsc: $LR lp=$LPKG lv=$LVER db=$DFILE"
