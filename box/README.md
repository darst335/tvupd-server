# 盒子端（Android 4.x IPTV 定制机）

让盒子接入 tvupd-server 的脚本集合。两条路：

## 路线 A：临时安装（不动固件，恢复出厂即消失）

要求：盒子已 root、网络 adb 已开（部分机型遥控器按 F3/F4 或工程菜单开）。

```sh
# 1. 先改 box/system/etc/tv-updater.conf 的 MANIFEST_URL 指向你的服务器
# 2. （可选）把自己的 adbkey.pub 复制为 box/tv-adbkey，实现免授权
sh install-to-box.sh 192.168.1.123        # 盒子 IP；adb 端口默认 30016
```

装了什么：
- `/system/bin/tv-updater` —— 主进程：拉清单 → md5 校验 → `pm install` 静默安装 / `pm uninstall`，
  执行方案里的 `cmd` 行（nonce 去重，每条只跑一次），心跳上报（机型/内存/已装应用/运行时长）
- `/system/bin/tv-maint` —— 维护循环：固定 DNS（防运营商劫持）、Wi-Fi 不休眠、
  内存回收、空闲时段自动重启
- `/system/bin/tv-oemctl` —— 运营商组件屏蔽（改名+替身的可逆方式，恢复出厂即还原）
- `/system/etc/install-recovery.sh(+2.sh)` —— 开机自启入口（挂在系统自带的
  `flash_recovery` 服务上；2.sh 用 `busybox setsid` 脱离进程组，避免被 init 连带杀掉）

## 路线 B：固件植入（批量出货零调试）

把上面这些文件直接打进刷机包（OTA zip 的 system/ 目录树），盒子刷完开机即带全套系统：

1. 解包 OTA（`update/` 目录树 + `boot.img`）
2. 把 `box/system/` 下的文件拷进 `update/system/` 对应位置
3. 如需开机自动开 adb：改 `boot.img` ramdisk 的 init.rc（`on boot` 段加
   `setprop persist.sys.debugenable 1`），`firmware/pack_boot.py` 可重打包 boot.img
   （解析原 cpio → 只换 init.rc → gzip → 重拼 ANDROID! 头，带自校验）
4. `firmware/write_fw.py` 把文件登记进 `META/filesystem_config.txt`（幂等）
5. 打 zip + 签名。老 recovery（Android 4.4）签名两个关键参数：
   ```sh
   java -jar apksigner.jar sign \
     --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
     --min-sdk-version 17 --v1-signer-name CERT \
     --key testkey.pk8 --cert testkey.x509.pem --out update_signed.zip update
   ```
   （`--v1-signer-name CERT`：老 recovery 硬编码只认 `META-INF/CERT.SF/CERT.RSA`；
   `--min-sdk-version 17`：让 V1 用 SHA1 摘要。JDK17 的 signapk.jar 已不可用。）
6. U 盘卡刷（FAT32 单分区，插靠网口的 USB 口）

## 盒子端配置（tv-updater.conf）

| 参数 | 说明 |
|---|---|
| MANIFEST_URL | 服务器清单地址（`/cgi-bin/manifest`），`group` 参数可分组灰度 |
| INTERVAL | 轮询间隔秒（默认 600） |
| REINSTALL_ON_FAIL | 安装失败是否先卸载再装（换签名包用） |
| ADB_AUTO | 开机自动开网络 adb（配合固件植入的属性触发） |
| DNS1/DNS2/DNS_FORCE | 维护用：固定公共 DNS |
| IDLE_HOUR_FROM/TO、IDLE_MIN_UP_H、IDLE_PKGS | 空闲时段自动重启策略 |

## 适配新机型

- `tv-oemctl` 的 OEM 组件清单要按目标固件的 init.rc 调整（`HOLD_BIN/HOLD_ETC/PKGS`）
- adb 端口：本套默认 30016（`service.adb.tcp.port`），和固件 ramdisk 的设置保持一致
- Android 4.4 的 `toolbox` 缺很多命令，脚本全部以 busybox 检测做了兼容（详见各脚本头部注释）
