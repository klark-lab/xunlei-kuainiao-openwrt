'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require poll';

var callInitAction = rpc.declare({
    object: 'luci',
    method: 'setInitAction',
    params: ['name', 'action'],
    expect: { result: false }
});

var callGetStatus = rpc.declare({
    object: 'luci',
    method: 'getInitStatus',
    params: ['name'],
    expect: { '': {} }
});

var callXunleiStatus = rpc.declare({
    object: 'xunlei-kuainiao',
    method: 'status',
    expect: { '': {} }
});

return view.extend({
    render: function() {
        var m, s, o;

        m = new form.Map('xunlei-kuainiao', _('迅雷快鸟提速'),
            _('通过迅雷快鸟服务提升宽带速度。需要迅雷VIP账号。'));

        // 基本设置
        s = m.section(form.TypedSection, 'main', _('基本设置'));
        s.anonymous = true;

        o = s.option(form.Flag, 'enabled', _('启用服务'));
        o.default = '0';
        o.rmempty = false;

        // 凭据配置
        s = m.section(form.TypedSection, 'main', _('凭据配置'));
        s.anonymous = true;

        o = s.option(form.Value, 'device_id', _('Device ID'),
            _('从浏览器开发者工具获取，详见说明'));
        o.placeholder = '请输入 x-device-id';
        o.rmempty = true;

        o = s.option(form.Value, 'refresh_token', _('Refresh Token'),
            _('从浏览器 Local Storage 获取，详见说明'));
        o.placeholder = '请输入 refresh_token';
        o.password = true;
        o.rmempty = true;

        o = s.option(form.Value, 'device_sign', _('Device Sign'),
            _('可选，通常留空即可'));
        o.placeholder = '可选';
        o.rmempty = true;

        // 自动续期设置
        s = m.section(form.TypedSection, 'main', _('自动续期设置'));
        s.anonymous = true;

        o = s.option(form.Flag, 'auto_renew', _('启用自动续期'));
        o.default = '1';
        o.rmempty = false;

        o = s.option(form.Value, 'renew_cron', _('Cron 表达式'),
            _('自动续期的定时任务，格式：分 时 日 月 周'));
        o.default = '15 3 * * *';
        o.placeholder = '15 3 * * *';
        o.rmempty = false;

        // 日志设置
        s = m.section(form.TypedSection, 'main', _('日志设置'));
        s.anonymous = true;

        o = s.option(form.ListValue, 'log_level', _('日志级别'));
        o.value('debug', _('调试'));
        o.value('info', _('信息'));
        o.value('warn', _('警告'));
        o.value('error', _('错误'));
        o.default = 'info';

        o = s.option(form.Value, 'state_file', _('状态文件路径'));
        o.default = '/var/lib/xunlei-kuainiao/state.json';

        // 状态显示
        s = m.section(form.NamedSection, 'main', 'xunlei-kuainiao', _('服务状态'));
        s.anonymous = true;

        o = s.option(form.DummyValue, '_status', _('当前状态'));
        o.rawhtml = true;
        o.default = '<em>加载中...</em>';

        // 说明
        s = m.section(form.NamedSection, 'main', 'xunlei-kuainiao', _('使用说明'));
        s.anonymous = true;

        o = s.option(form.DummyValue, '_help', _('获取凭据方法'));
        o.rawhtml = true;
        o.default = [
            '<div style="background:#f9f9f9;padding:15px;border-radius:5px;margin:10px 0;">',
            '<h3>获取凭据步骤：</h3>',
            '<ol>',
            '<li>在浏览器登录迅雷账号中心 (<a href="https://i.xunlei.com" target="_blank">i.xunlei.com</a>)</li>',
            '<li>打开开发者工具（F12）</li>',
            '<li><strong>获取 Refresh Token：</strong><br>',
            'Application → Local Storage → <code>https://i.xunlei.com</code><br>',
            '找到 <code>credentials_XW5SkOhLDjnOZP7J</code>，复制 JSON 中的 <code>refresh_token</code></li>',
            '<li><strong>获取 Device ID：</strong><br>',
            'Network 标签 → 查找发往 <code>xluser-ssl.xunlei.com</code> 的请求<br>',
            '复制请求头中的 <code>x-device-id</code></li>',
            '</ol>',
            '<p><strong>注意：</strong>Refresh Token 会自动轮换，请勿使用旧 Token。</p>',
            '</div>'
        ].join('\n');

        // 添加状态刷新按钮
        s = m.section(form.NamedSection, 'main', 'xunlei-kuainiao', _('操作'));
        s.anonymous = true;

        o = s.option(form.Button, '_refresh_status', _('刷新状态'));
        o.inputstyle = 'action';
        o.onclick = function() {
            window.location.reload();
        };

        o = s.option(form.Button, '_run_now', _('立即执行提速'));
        o.inputstyle = 'positive';
        o.onclick = function() {
            if (confirm('确定要立即执行提速吗？')) {
                // 这里需要通过 ubus 或 rpc 调用执行命令
                alert('请在终端执行：xunlei-kuainiao-cli run');
            }
        };

        return m.render();
    }
});
