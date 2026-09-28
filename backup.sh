#!/bin/sh
# 打包全部业务数据（方案/档案表/管理密码/指令回执/访问日志/APK 库/中文名/包名缓存/系统设置）
# 产物在当前目录：tvupd-backup-<日期>.tar.gz —— 拷到新路由器后用 restore.sh 导入
set -e
OUT="tvupd-backup-$(date '+%Y%m%d-%H%M%S').tar.gz"
tar -czf "/tmp/$OUT" \
    /srv/tvupd-priv \
    /srv/tvupd/apks \
    /srv/tvupd/apps.txt 2>/dev/null || true
mv "/tmp/$OUT" .
echo "备份完成: $(pwd)/$OUT"
echo "传到新路由器:  scp $OUT root@<新路由器IP>:/tmp/  然后在新机上: sh restore.sh /tmp/$OUT"
