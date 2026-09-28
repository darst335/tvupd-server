#!/system/bin/sh
# install-recovery-2.sh —— 开机自启入口
#   由 /system/etc/install-recovery.sh 调用；后者是 init.rc 里
#   service flash_recovery 的 oneshot 入口（本机型固件自带该 service 定义）
#
# v3（2026-09-23）在 v2 清理版基础上增加「日常维护」，历史改动说明保留在下方：
#   移除 1) busybox telnetd 明文 root 后门（该命令在本机 busybox 上无 telnetd applet，
#            属死代码；且 init.rc 里另有 disabled 的 telnetd 服务，留着容易被误启用）
#   移除 2) mount -o remount,rw /system —— 原脚本每次开机把系统分区挂成可写
#   移除 3) setprop service.adb.tcp.enable 1 —— 本固件走框架响应，重启后经常不生效
#   移除 4) 每次开机重写 settings.db 的 sqlite 语句 —— 值已持久化，冗余
#   保留   / 网络 adb（5555）可靠自启、tv-updater 应用自维护器
#   新增   / tv-updater 看门狗；日常维护循环（DNS / Wi-Fi / 内存 / 缓存 / 空闲重启 / OEM 屏蔽）
#
# 本机 shell 无 printf，全部用 echo。

setprop persist.sys.usb.config mtp,adb

# 1) 网络 adb 自启
#    本机型的 adbd 是 disabled 服务，靠属性触发：
#        init.rc: on property:persist.sys.debugenable=1 -> start console; start adbd
#    （遥控器 F3/F4「开 ADB」设的就是这个属性）
#    批量出货的盒子不可能逐台按遥控器，这里开机自动设一次（persist，永久生效）。
#    端口沿用固件默认的 30016（init.rc 开机已 setprop service.adb.tcp.port 30016）。
#    配置里 ADB_AUTO=0 可关掉（不想常开 adb 的客户群）。
[ -f /system/etc/tv-updater.conf ] && . /system/etc/tv-updater.conf
if [ "$ADB_AUTO" != "0" ]; then
    setprop service.adb.tcp.port 30016
    setprop persist.sys.debugenable 1
fi

# 2) adb 免授权：把固件里预置的公钥写进 /data/misc/adb/adb_keys。
#    本机型 ro.adb.secure=1，新刷的盒子第一次 adb connect 会在电视上弹「允许
#    USB 调试」确认框 —— 批量出货不可能逐台拿遥控器点，这里开机自动授信。
(
    sleep 20
    if [ -f /system/etc/tv-adbkey ]; then
        mkdir -p /data/misc/adb 2>/dev/null
        K=/data/misc/adb/adb_keys
        [ -f "$K" ] || : > "$K"
        # 不能用 while read：tv-adbkey 末尾没有换行符，read 会直接返回失败读 0 行
        L=$(cat /system/etc/tv-adbkey)
        case "$(cat "$K" 2>/dev/null)" in
            *"$L"*) ;;                      # 已授信，跳过（幂等）
            *) echo "$L" >> "$K" ;;
        esac
        chmod 600 "$K" 2>/dev/null
        chown 1000:2000 "$K" 2>/dev/null
    fi
) &

# 2) 应用自维护器：轮询清单自动装/更/删/执行远程指令
/system/bin/tv-updater &

# 3) updater 看门狗：低内存被回收或异常退出后自动拉起
#    判据 = 锁文件里的 PID 是否存活，或 last.log 长时间没更新（说明卡死挂起）
#    陈旧阈值跟随轮询间隔（3 倍间隔 + 10 分钟），避免以后调大 INTERVAL 被误判
INTERVAL=600
[ -f /system/etc/tv-updater.conf ] && . /system/etc/tv-updater.conf
WATCH_INTERVAL=${INTERVAL:-600}
case "$WATCH_INTERVAL" in *[!0-9]*|"") WATCH_INTERVAL=600 ;; esac
STALE_MIN=$(( WATCH_INTERVAL / 60 * 3 + 10 ))
(
    while :; do
        sleep 300
        P=$(cat /data/local/tv-updater/lock 2>/dev/null)
        # 冷启动时钟未对时时（2015 年）时间戳比较没有意义，跳过陈旧判定
        OLD=""
        Y=$(date +%Y 2>/dev/null)
        case "$Y" in ''|*[!0-9]*) ;; *) [ "$Y" -ge 2020 ] && OLD=$(find /data/local/tv-updater/last.log -mmin +$STALE_MIN 2>/dev/null) ;; esac
        if [ -z "$P" ] || ! kill -0 "$P" 2>/dev/null || [ -n "$OLD" ]; then
            [ -n "$P" ] && kill "$P" 2>/dev/null
            /system/bin/tv-updater &
        fi
    done
) &

# 4) 日常维护循环（每 30 分钟一拍）
#    备注：老盒子连续跑几天会内存碎片化、直播卡顿；这里做常态化收敛，不需要客户动手。
(
    sleep 120
    /system/bin/tv-maint all        # 开机：固定 DNS / Wi-Fi 策略 / 内存回收 / 重新屏蔽 OEM 组件
    M=/data/local/tv-updater
    while :; do
        sleep 1800
        /system/bin/tv-maint mem            # 可用内存低于阈值才做（drop_caches + am kill-all）
        /system/bin/tv-maint dns            # 定期复检公共 DNS（DHCP 续租可能把它改回去）
        /system/bin/tv-maint idle-reboot    # 仅凌晨 + 已运行很久 + 当前无播放时重启

        # 每日：强制内存回收 + Wi-Fi 策略复检 + OEM 屏蔽复检
        D=$(date +%F)
        if [ "$(cat $M/.lastdaily 2>/dev/null)" != "$D" ]; then
            /system/bin/tv-maint mem force
            /system/bin/tv-maint wifi
            /system/bin/tv-maint oem
            echo "$D" > "$M/.lastdaily"

            # 每周（按"日常维护成功执行 7 次"计数，跨重启也不丢）：清应用缓存
            N=$(cat $M/.cachecnt 2>/dev/null)
            case "$N" in ''|*[!0-9]*) N=0 ;; esac
            N=$((N + 1))
            if [ "$N" -ge 7 ]; then
                N=0
                /system/bin/tv-maint cache
            fi
            echo "$N" > "$M/.cachecnt"
        fi
    done
) &
