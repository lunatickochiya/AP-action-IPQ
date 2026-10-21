'use strict';
'require baseclass';
'require fs';
'require rpc';
'require uci';

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board',
	expect: {}
});

var callCPUInfo = rpc.declare({
	object: 'luci',
	method: 'getCPUInfo',
	expect: {}
});

var callCPUUsage = rpc.declare({
	object: 'luci',
	method: 'getCPUUsage',
	expect: {}
});

var callTempInfo = rpc.declare({
	object: 'luci',
	method: 'getTempInfo',
	expect: {}
});

var callOnlineUsers = rpc.declare({
	object: 'luci',
	method: 'getOnlineUsers',
	expect: {}
});

var callCPUBench = rpc.declare({
	object: 'luci',
	method: 'getCPUBench',
	expect: {}
});

/* 固件编译时间：优先使用 ubus system board 的 release.builddate，
 * 老版本 procd 不返回该字段时回退解析 /usr/lib/os-release 的 OPENWRT_BUILD_DATE */
function parseBuildDate(board, osrelease) {
	var ts = board?.release?.builddate;

	if (!ts && osrelease) {
		var m = String(osrelease).match(/^OPENWRT_BUILD_DATE="?([0-9]+)"?$/m);
		if (m)
			ts = m[1];
	}

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

function parseCpuMark(txt) {
	var m = String(txt || '').match(/CpuMark\s*:\s*([0-9.]+)/);
	return m ? parseFloat(m[1]).toFixed(1) : null;
}

/* 打了 luci-base ext cpu usage 补丁时 getCPUUsage 直接返回 /sbin/usage 的
 * 完整结果（"CPU: 3% NPU: 12 ECM: 356"）；没打补丁时只有裸百分比，
 * 此时由前端自己调用 /sbin/usage，两者行为保持一致 */
function isExtendedUsage(txt) {
	return /CPU:/i.test(String(txt || ''));
}

function usageText(raw) {
	var s = String(raw == null ? '' : raw).trim();

	if (!s || s === '?')
		return s;

	if (!isExtendedUsage(s) && /^[0-9.]+%?$/.test(s))
		return 'CPU: ' + s + (/%$/.test(s) ? '' : '%');

	return s;
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
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callCPUInfo(), {}),
			L.resolveDefault(callCPUUsage(), {}),
			L.resolveDefault(callTempInfo(), {}),
			L.resolveDefault(callOnlineUsers(), {}),
			L.resolveDefault(callCPUBench(), {}),
			uci.load('system')
		]).then(function(data) {
			var osrelease = !data[0]?.release?.builddate
				? L.resolveDefault(fs.read('/usr/lib/os-release'), '')
				: Promise.resolve('');

			var usagestat = isExtendedUsage(data[2]?.cpuusage)
				? Promise.resolve(null)
				: L.resolveDefault(fs.exec('/sbin/usage'), null);

			return Promise.all([ osrelease, usagestat ]).then(function(extra) {
				data[7] = extra[0] || '';
				data[8] = extra[1];
				return data;
			});
		});
	},

	render: function(data) {
		data = data || [];

		var board     = data[0] || {},
		    cpuinfo   = data[1] || {},
		    cpuusage  = data[2] || {},
		    tempinfo  = data[3] || {},
		    users     = data[4] || {},
		    cpubench  = data[5] || {},
		    osrelease = data[7] || '',
		    usageout  = data[8] && data[8].stdout ? String(data[8].stdout).trim() : '';

		var cpumark = parseCpuMark(cpubench.cpubench),
		    usage = usageout || usageText(cpuusage.cpuusage);

		return E('table', { 'class': 'table' }, [
			row('固件编译时间', E('span', {}, parseBuildDate(board, osrelease))),
			row('CPU 信息', text(cpuinfo.cpuinfo)),
			row('温度', text(tempinfo.tempinfo)),
			row('使用率', text(usage)),
			row('在线用户', text((users.onlineusers != null) ? String(users.onlineusers) : null)),
			row('CPU 跑分', E('span', {}, cpumark ? ('CpuMark ' + cpumark + ' 分') : '—')),
			sourceRow()
		]);
	}
});
