'use strict';
'require baseclass';
'require fs';
'require uci';

var SYSINFO_HELPER = '/usr/libexec/autoset/sysinfo';

/* 固件编译时间：helper 输出 os-release 里的 OPENWRT_BUILD_DATE（Unix 时间戳） */
function fmtBuildDate(ts) {
	ts = parseInt(ts, 10);
	if (!ts)
		return '—';

	var date = new Date(ts * 1000);
	if (isNaN(date.getTime()))
		return '—';

	var opts = { dateStyle: 'medium', timeStyle: 'short' },
	    tz = uci.get('system', '@system[0]', 'zonename');

	if (tz)
		opts.timeZone = tz.replace(/ /g, '_');

	try {
		return new Intl.DateTimeFormat(undefined, opts).format(date);
	}
	catch (e) {
		return date.toLocaleString();
	}
}

/* helper 输出 KEY=VALUE，一行一项 */
function parseKV(out) {
	var kv = {};

	String(out || '').split('\n').forEach(function(line) {
		var pos = line.indexOf('=');

		if (pos > 0)
			kv[line.substring(0, pos)] = line.substring(pos + 1);
	});

	return kv;
}

function text(txt) {
	return E('span', { 'style': 'white-space:pre-line' },
		(txt == null || txt === '') ? '—' : txt);
}

function row(label, valueEl) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, [ label ]),
		E('td', { 'class': 'td left', 'colspan': '2' }, [ valueEl ])
	]);
}

function sourceRow() {
	return row('源代码', E('span', {}, [
		E('a', {
			'href': 'https://github.com/lunatickochiya',
			'target': '_blank',
			'rel': 'noopener'
		}, [ 'Project OpenWrt' ]),
		' / ',
		E('a', {
			'href': 'https://github.com/lunatickochiya/AP-action',
			'target': '_blank',
			'rel': 'noopener'
		}, [ 'Powered By 2U4U' ])
	]));
}

return baseclass.extend({
	title: '系统信息',

	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec(SYSINFO_HELPER), null),
			uci.load('system')
		]);
	},

	render: function(data) {
		data = data || [];

		var kv = parseKV(data[0] && data[0].stdout),
		    cpumark = parseFloat(kv.CPUBENCH);

		return E('table', { 'class': 'table' }, [
			row('固件编译时间', E('span', {}, fmtBuildDate(kv.BUILDDATE))),
			row('CPU 信息', text(kv.CPUINFO)),
			row('温度', text(kv.TEMPINFO)),
			row('使用率', text(kv.USAGE)),
			row('在线用户', text(kv.USERS)),
			row('CPU 跑分', E('span', {}, isFinite(cpumark) ? ('CpuMark ' + cpumark.toFixed(1) + ' 分') : '—')),
			sourceRow()
		]);
	}
});
