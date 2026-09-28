#!/bin/sh
# 导入 backup.sh 生成的数据包：sh restore.sh /tmp/tvupd-backup-xxx.tar.gz
set -e
[ -n "$1" ] && [ -f "$1" ] || { echo "用法: sh restore.sh <tvupd-backup-xxx.tar.gz>"; exit 1; }
mkdir -p /srv/tvupd/apks
tar -xzf "$1" -C /
mkdir -p /srv/tvupd-priv/ipcache /srv/tvupd-priv/plans
# 从备份里恢复系统设置（若有），没有则保持 install.sh 生成的
[ -f /srv/tvupd-priv/settings.env ] || printf 'SRCNET="%s"\n' "$(uci -q get network.lan.ipaddr | awk -F. '{print $1"."$2"."$3"."}')" > /srv/tvupd-priv/settings.env
chmod 600 /srv/tvupd-priv/admin.pwd 2>/dev/null || true
/etc/init.d/lighttpd restart 2>/dev/null || true
echo "数据导入完成。记得在控制台「系统设置」里把对外服务地址改成新路由器的地址。"
