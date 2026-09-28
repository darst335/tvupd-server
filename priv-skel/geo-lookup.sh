#!/bin/sh
# geo-lookup —— 盒子客户分布报告
# 读 access.log（时间|序列号|MAC|IP|安卓SDK|机型|方案|备注），对每个公网 IP
# 调 ip-api.com 中文接口解析归属地，缓存查询结果，输出报表到 locations.txt
PRIV=/srv/tvupd-priv
LOGF=$PRIV/access.log
OUT=$PRIV/locations.txt
CACHE=$PRIV/ipcache

mkdir -p "$CACHE" 2>/dev/null
[ -s "$LOGF" ] || { echo "access.log 为空"; exit 0; }

# 日志瘦身：只保留最近 8000 行
WL=$(wc -l < "$LOGF")
if [ "$WL" -gt 8000 ]; then
    tail -n 8000 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
fi

# 每台盒子取最新一条记录（按 id 去重，无 id 的按 ip）
awk -F'|' '{k=($2!=""?$2:"noip-"$4); r[k]=$0} END{for(i in r) print r[i]}' "$LOGF" > "$PRIV/.latest"

: > "$OUT"
echo "=== 盒子客户分布报告 $(date '+%Y-%m-%d %H:%M') ===" >> "$OUT"
echo "最后在线|序列号|IP|机型|安卓|方案|备注|归属地|运营商" >> "$OUT"

while IFS='|' read -r DT ID MAC IP SDK MODEL PLAN NOTE; do
    case "$IP" in
        192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|127.*|""|-)
            GEO=内网/本机; ISP=-
            ;;
        *)
            CF="$CACHE/$IP"
            if [ -s "$CF" ]; then
                GEO=$(sed -n 1p "$CF"); ISP=$(sed -n 2p "$CF")
            else
                T=/tmp/geo.$$
                wget -q -O "$T" -T 8 \
                    "http://ip-api.com/line/$IP?fields=status,country,regionName,city,isp&lang=zh-CN" 2>/dev/null
                if [ -s "$T" ] && [ "$(sed -n 1p "$T")" = "success" ]; then
                    GEO="$(sed -n 3p "$T")$(sed -n 4p "$T")"
                    ISP=$(sed -n 5p "$T")
                    printf '%s\n%s\n' "$GEO" "$ISP" > "$CF"
                else
                    GEO=查询失败; ISP=-
                fi
                rm -f "$T"
            fi
            ;;
    esac
    echo "$DT|$ID|$IP|${MODEL:--}|${SDK:--}|$PLAN|$NOTE|$GEO|$ISP" >> "$OUT"
done < "$PRIV/.latest"

rm -f "$PRIV/.latest"
echo "report written: $OUT"
cat "$OUT"
