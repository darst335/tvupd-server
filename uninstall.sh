#!/bin/sh
# 卸载 TV 盒子自维护分发系统（默认保留数据，加 PURGE=1 连数据一起删）
set -e
/etc/init.d/lighttpd stop 2>/dev/null || true
/etc/init.d/lighttpd disable 2>/dev/null || true
rm -f /www/luci-static/resources/view/tvupd/admin.js
rmdir /www/luci-static/resources/view/tvupd 2>/dev/null || true
if [ -f /etc/lighttpd/lighttpd.conf.tvupd-bak ]; then
    mv /etc/lighttpd/lighttpd.conf.tvupd-bak /etc/lighttpd/lighttpd.conf
    echo "已恢复原 lighttpd 配置"
fi
if [ "${PURGE:-0}" = "1" ]; then
    printf '将删除 /srv/tvupd 与 /srv/tvupd-priv 全部数据（方案/档案/APK库），输入 yes 确认: '
    read -r A
    [ "$A" = "yes" ] || { echo "取消"; exit 0; }
    rm -rf /srv/tvupd /srv/tvupd-priv
    echo "数据已删除"
else
    echo "数据保留在 /srv/tvupd-priv 与 /srv/tvupd（可重装后继续用，或用 backup.sh 打包带走）"
fi
/etc/init.d/lighttpd start 2>/dev/null || true
echo "卸载完成"
