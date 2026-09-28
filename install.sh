#!/bin/sh
# ============================================================
# TV 盒子自维护分发系统 —— OpenWrt 一键安装
#
# 用法（在仓库目录里）：
#   sh install.sh                          # 全自动（自动探测网段、随机密码）
#   PORT=8090 sh install.sh                # 指定端口
#   SRVURL="http://盒 子域名:8083" sh install.sh   # 指定对外地址（DDNS 域名等）
#   ADMIN_PWD=mypass123 sh install.sh      # 指定管理密码
#   SRCNET=192.168.9. sh install.sh        # 指定管理白名单网段前缀
#
# 可重复执行：已有数据（devices.txt/方案/APK 库）不会被覆盖。
# ============================================================
set -e

PORT="${PORT:-8083}"
SRVURL="${SRVURL:-}"
ADMIN_PWD="${ADMIN_PWD:-}"
SRCNET="${SRCNET:-}"

BASE=$(cd "$(dirname "$0")" && pwd)

echo "== [1/6] 安装依赖 lighttpd + cgi + setenv =="
opkg update >/dev/null 2>&1 || true
opkg install lighttpd lighttpd-mod-cgi lighttpd-mod-setenv >/dev/null 2>&1 || true
opkg list-installed | grep -q lighttpd-mod-cgi || { echo "错误：lighttpd-mod-cgi 安装失败，检查网络/软件源"; exit 1; }

echo "== [2/6] 读取路由器当前配置 =="
LANIP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
SRCNET=$(printf '%s' "$LANIP" | awk -F. '{print $1"."$2"."$3"."}')
[ -n "$SRVURL" ] || SRVURL="http://$LANIP:$PORT"
if [ -z "$ADMIN_PWD" ]; then
    ADMIN_PWD=$(head -c 16 /dev/urandom | md5sum | tr -cd 'a-z0-9' | cut -c1-8)
fi

echo "== [3/6] 落位服务文件 /srv/tvupd =="
mkdir -p /srv/tvupd/cgi-bin /srv/tvupd/apks /srv/tvupd/scripts
mkdir -p /srv/tvupd-priv/plans /srv/tvupd-priv/ipcache
install -m 644 "$BASE/www/admin.html" /srv/tvupd/admin.html
install -m 755 "$BASE/www/admin" /srv/tvupd/admin
ln -sf ../admin /srv/tvupd/cgi-bin/admin
install -m 755 "$BASE/www/manifest" /srv/tvupd/cgi-bin/manifest
[ -f "$BASE/www/apps.txt" ] && install -m 644 "$BASE/www/apps.txt" /srv/tvupd/apps.txt
[ -f "$BASE/www/fixadb.sh" ] && install -m 755 "$BASE/www/fixadb.sh" /srv/tvupd/fixadb.sh

echo "== [4/6] 初始化数据目录 /srv/tvupd-priv（已有数据不覆盖）=="
[ -f /srv/tvupd-priv/devices.txt ] || install -m 644 "$BASE/priv-skel/devices.txt" /srv/tvupd-priv/devices.txt
for p in "$BASE"/priv-skel/plans/*.txt; do
    [ -e "$p" ] || continue
    f=$(basename "$p")
    [ -f "/srv/tvupd-priv/plans/$f" ] || install -m 644 "$p" "/srv/tvupd-priv/plans/$f"
done
[ -f /srv/tvupd-priv/geo-lookup.sh ] || install -m 755 "$BASE/priv-skel/geo-lookup.sh" /srv/tvupd-priv/geo-lookup.sh
printf '%s\n' "$ADMIN_PWD" > /srv/tvupd-priv/admin.pwd
chmod 600 /srv/tvupd-priv/admin.pwd
cat > /srv/tvupd-priv/settings.env <<EOF
SRVURL="$SRVURL"
SRCNET="$SRCNET"
ONLINE_H="24"
EOF

echo "== [5/6] 配置并启动 lighttpd（端口 $PORT）=="
[ -f /etc/lighttpd/lighttpd.conf ] && [ ! -f /etc/lighttpd/lighttpd.conf.tvupd-bak ] && \
    cp -a /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.tvupd-bak
cat > /etc/lighttpd/lighttpd.conf <<EOF
# lighttpd —— TV 盒子自维护分发服务（由 tvupd-server install.sh 生成）
server.modules = ( "mod_indexfile", "mod_access", "mod_cgi", "mod_accesslog", "mod_setenv" )

server.port = $PORT
server.bind = "0.0.0.0"
server.document-root = "/srv/tvupd"
server.upload-dirs = ( "/tmp" )
server.errorlog = "/srv/tvupd-priv/lighttpd-error.log"
accesslog.filename = "/srv/tvupd-priv/lighttpd-access.log"

index-file.names = ( "index.html" )
cgi.assign = ( "manifest" => "", "admin" => "" )

mimetype.assign = (
    ".txt" => "text/plain; charset=utf-8",
    ".apk" => "application/vnd.android.package-archive",
    ".html" => "text/html",
    "" => "application/octet-stream"
)

server.max-connections = 128
connection.kbytes-per-second = 4096

# 管理台页面禁止缓存
\$HTTP["url"] =~ "^/admin\\.html$" {
    setenv.add-response-header = ( "Cache-Control" => "no-cache, must-revalidate" )
}

# 管理控制台仅限局域网网段（外网访问 admin 一律 403）
\$HTTP["remoteip"] != "${SRCNET}0/24" {
    \$HTTP["url"] =~ "^/(admin\\.html|cgi-bin/admin)" { url.access-deny = ("") }
}
EOF
/etc/init.d/lighttpd enable 2>/dev/null || true
/etc/init.d/lighttpd restart

echo "== [6/6] LuCI 菜单（可选，检测到 LuCI 才装）=="
if [ -d /www/luci-static/resources/view ]; then
    mkdir -p /www/luci-static/resources/view/tvupd
    install -m 644 "$BASE/luci/admin.js" /www/luci-static/resources/view/tvupd/admin.js
    echo "  已安装：LuCI → 服务 → TV盒子运维控制台（iframe 内嵌本控制台）"
else
    echo "  未检测到 LuCI 视图目录，跳过（不影响使用）"
fi

echo
echo "============================================================"
echo " 安装完成！"
echo "   控制台:  http://$LANIP:$PORT/admin.html"
echo "   管理密码: $ADMIN_PWD   （请立即登录并在「系统设置」里改掉）"
echo "   对外地址: $SRVURL   （换域名/换路由后在控制台「系统设置」里改）"
echo "   盒子端:  无需配置，只要能访问 http://$SRVURL/cgi-bin/manifest"
echo "   数据目录: /srv/tvupd-priv（迁移时用 backup.sh / restore.sh）"
echo "============================================================"
