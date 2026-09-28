酷9 泉州台式分发：
- ku9-conf-tpl.json 放 /srv/tvupd-priv/（@LIVE@ 为每盒订阅地址占位符）
- ku9-list.txt 放 /srv/tvupd-priv/（你的频道列表，属于核心资产，不要提交到任何公开仓库）
- ku9-allow.txt 放 /srv/tvupd-priv/（一行一个授权序列号，删行=吊销）
- ku9-setup.sh 放 /srv/tvupd/ku9/（盒子端由 sh 指令拉取执行）
- 频道列表中的本地 JS 写法 http://A/ku9/js/xxx.js 走盒子本地 /sdcard/酷9/js/xxx.js
