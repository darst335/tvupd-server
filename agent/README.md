# TV管家（agent）—— 免刷固件盒子的用户级控制端

面向"不方便刷固件"的客户盒子：一个普通 APK，实现与固件端 tv-updater 相同协议的管理通道。

## 能力边界（Android 4.4+，无 root）
- 轮询 manifest：心跳（序列号/MAC/机型/运行时长/内存/应用清单）+ 方案拉取
- install 行：下载 → md5 校验 → 拉起系统安装器（客户按一次确认键）；有 root 则静默安装
- remove 行：root 静默卸载；否则拉起卸载确认（每包只提示一次）
- cmd 动作：report / msg(电视弹字) / open(启动指定应用) / ku9(部署酷9三件套并拉起) / sh(root 时执行，无 root 且为酷9脚本则原生等效部署) / reboot(仅 root)
- 开机自启；/sdcard/tvbutler.conf 可覆盖 SRV= 与 POLL=

## 酷9 场景（无需 root）
ku9 动作 = 写 /sdcard/酷9/{js,logo,configuration} 三件套（Configuration.json 由服务器按
序列号生成、含每盒专属订阅地址）→ 启动酷9 → 预置订阅在首启生效。

## 构建
无需 Android Studio：JDK17 + build-tools r34 + API19/35 platform jar，见 build.sh。
签名：项目内自建 keystore（tvbutler.jks），apksigner 仅 V1 + SHA1 摘要（--min-sdk-version 17），
JDK17 的 jarsigner 已禁 SHA1 不能用。

## 服务器端
无任何改动——manifest/ku9cfg/ku9pl 按序列号授权的机制与固件端共用。
