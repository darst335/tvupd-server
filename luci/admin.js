'use strict';
'require view';
'require dom';

/*
 * TV盒子运维控制台 —— LuCI 内嵌视图
 * 直接 iframe 路由器 8083 端口上的独立管理控制台（lighttpd 托管），
 * 主机名动态取自当前访问地址，兼容 IP / 域名两种访问方式。
 * iframe 地址带时间戳参数，强制每次取最新页面（admin.html 本身也已发 no-cache 头）。
 */
return view.extend({
	render: function () {
		var host = window.location.hostname;
		var url = 'http://' + host + ':8083/admin.html?v=' + Date.now();

		var frame = E('iframe', {
			src: url,
			style: 'width:100%;height:calc(100vh - 160px);min-height:560px;' +
				'border:1px solid #d1d1d1;border-radius:3px;background:#fff;'
		});

		var desc = E('div', { 'class': 'cbi-map-descr' }, [
			E('p', {}, _('统一管理电视盒子：在线状态、软件方案分配、APK 库、客户归属地分布。')),
			E('p', {}, _('控制台由路由器 8083 端口独立服务（仅限局域网访问），与 LuCI 登录相互独立。') + ' ' +
				E('a', { 'href': 'http://' + host + ':8083/admin.html', 'target': '_blank', 'style': 'font-weight:bold' },
					_('在新窗口打开 ↗')))
		]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('TV盒子运维控制台')),
			desc,
			frame
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
