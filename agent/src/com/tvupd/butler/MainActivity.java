package com.tvupd.butler;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/** 状态屏：序列号/服务器/最近检查时间 + 立即检查 / 部署酷9配置 两个按键 */
public class MainActivity extends Activity {

    private TextView tv;

    @Override
    public void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(48, 48, 48, 48);
        root.setBackgroundColor(Color.rgb(16, 24, 38));

        TextView title = new TextView(this);
        title.setText("TV管家");
        title.setTextColor(Color.WHITE);
        title.setTextSize(30);
        title.setTypeface(null, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        tv = new TextView(this);
        tv.setTextColor(Color.rgb(180, 200, 220));
        tv.setTextSize(16);
        tv.setLineSpacing(6, 1);
        tv.setPadding(0, 32, 0, 32);
        root.addView(tv);

        root.addView(btn("立即检查", new Runnable() { public void run() {
            Intent i = new Intent(MainActivity.this, PollService.class);
            i.setAction("check_now");
            startService(i);
            refresh();
        }}));

        root.addView(btn("部署酷9配置", new Runnable() { public void run() {
            new Thread() { public void run() {
                final String srv = Util.conf(MainActivity.this)[0];
                // 直接调服务的部署逻辑：起服务并发 ku9 动作不合适，这里独立执行同款部署
                boolean ok = ku9Deploy(srv);
                runOnUiThread(new Runnable() { public void run() {
                    tv.append("\n酷9配置部署: " + (ok ? "完成" : "失败（检查服务器/授权名单）"));
                }});
            }}.start();
            refresh();
        }}));

        setContentView(root);
    }

    private Button btn(String text, final Runnable r) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(18);
        b.setPadding(0, 12, 0, 12);
        b.setOnClickListener(new android.view.View.OnClickListener() {
            public void onClick(android.view.View v) { r.run(); }
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = 16;
        b.setLayoutParams(lp);
        return b;
    }

    /** 与 PollService.deployKu9 相同的部署（按钮直调，无需经服务） */
    private boolean ku9Deploy(String srv) {
        try {
            String base = android.os.Environment.getExternalStorageDirectory()
                    .getAbsolutePath() + "/酷9";
            String sn = Util.serial();
            boolean ok = true;
            String[][] dirs = { {"js", "JS"}, {"logo", "Logo"}, {"configuration", "Configuration"} };
            for (String[] d : dirs) {
                new java.io.File(base + "/" + d[0]).mkdirs();
                new java.io.File(base + "/" + d[1]).mkdirs();
            }
            ok &= Util.download(srv + "/ku9/quanzhou.js", base + "/js/quanzhou.js");
            ok &= Util.download(srv + "/ku9/epg_data.json", base + "/logo/epg_data.json");
            ok &= Util.download(srv + "/cgi-bin/admin?op=ku9cfg&sn=" + sn,
                    base + "/configuration/Configuration.json");
            java.io.File cfg = new java.io.File(base + "/configuration/Configuration.json");
            if (!cfg.isFile() || !new String(Util.readFilePub(cfg), "UTF-8").contains("LIVE_URLS"))
                return false;
            return ok;
        } catch (Throwable t) { return false; }
    }

    @Override
    protected void onResume() { super.onResume(); refresh(); }

    private void refresh() {
        String[] conf = Util.conf(this);
        String last = PollService.LAST_CHECK == 0 ? "还没联系过服务器"
                : new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.US)
                        .format(new java.util.Date(PollService.LAST_CHECK));
        String root = Util.hasRoot() ? "有 root（全自动模式）" : "无 root（安装需按一次确认）";
        tv.setText("序列号: " + Util.serial()
                + "\nMAC: " + Util.mac()
                + "\n机型: " + Util.model() + "  (安卓 " + Util.sdk() + ")"
                + "\n服务器: " + conf[0]
                + "\n轮询间隔: " + conf[1] + " 分钟"
                + "\n最近检查: " + last
                + "\n状态: " + PollService.STATUS
                + "\n模式: " + root);
    }
}
