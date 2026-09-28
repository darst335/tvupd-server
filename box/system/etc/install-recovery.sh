#!/system/bin/sh
# install-recovery.sh —— 开机入口
#
# init.rc 里的定义（本机型固件自带，无需改 boot.img）：
#     service flash_recovery /system/etc/install-recovery.sh
#         class main
#         oneshot
#
# ⚠ 关键坑：init 对 oneshot 服务，在主进程退出后会 kill 掉它的整个进程组。
#   所以这里必须用 setsid 把真正干活的 install-recovery-2.sh 脱离出进程组，
#   否则刚拉起的 tv-updater / 看门狗会被一起杀掉，表现就是"脚本没执行"。
#
# 另外：adbd 端口由 init.rc 开机时 setprop service.adb.tcp.port 30016 设定，
#       本脚本不重启 adbd（避免踢掉正在运维的连接）。

/system/bin/mkdir -p /data/local/tv-updater 2>/dev/null
/system/bin/chmod 777 /data/local/tv-updater 2>/dev/null

if [ -x /system/bin/busybox ]; then
    /system/bin/busybox setsid /system/etc/install-recovery-2.sh \
        >>/data/local/tv-updater/boot.log 2>&1 &
else
    /system/etc/install-recovery-2.sh >>/data/local/tv-updater/boot.log 2>&1 &
fi

exit 0
