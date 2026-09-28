酷9 泉州台式分发：
- ku9-conf-tpl.json 放 /srv/tvupd-priv/（@LIVE@ 为每盒订阅地址占位符）
- ku9-list.txt 放 /srv/tvupd-priv/（你的频道列表，属于核心资产，不要提交到任何公开仓库）
- ku9-allow.txt 放 /srv/tvupd-priv/（一行一个授权序列号，删行=吊销）
- ku9-setup.sh 放 /srv/tvupd/ku9/（盒子端由 sh 指令拉取执行）
- 频道列表中的本地 JS 写法 http://A/ku9/js/xxx.js 走盒子本地 /sdcard/酷9/js/xxx.js
- ku9-setup.sh 末尾调 op=scset 拉取首页快捷图标注入脚本（当贝桌面）：
  - sc-icon-tpl.sh 放 /srv/tvupd/ku9/（模板，含 @SRV@ @POS@ @PKG@ @ALIAS@ 占位符）
  - 控制台方案编辑页有「生成图标指令」按钮，按 位置/包名/显示名 生成 cmd|sh 行
  - 注入脚本自动适配多版本当贝（com.dangbei1.tvlauncher 老版 Shortcut 表已实测；
    com.dangbei.tvlauncher 8.x 无 Shortcut 表 → 上报 nodb + 数据库清单，待逆向）
  - 注入结果经 op=devrep 回报 launcher.log，控制台总览「桌面」列展示版本与结果
  - 兼容精简 toolbox 固件：缺 head/tr/printf 的机型全部命令走 busybox；
    pm path 对不存在包返回 0 的机型按输出内容判断
