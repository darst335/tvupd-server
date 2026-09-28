package com.tvupd.butler;

import android.app.Notification;
import android.app.Service;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.widget.Toast;

import java.io.File;
import java.util.List;

/**
 * TV管家核心：轮询 manifest（协议与固件端 tv-updater 完全兼容），处理：
 *   install|包名|md5|url  —— root 静默装；否则下载校验后拉起系统安装器（用户按一次确认）
 *   remove|包名           —— root 静默卸载；否则拉起卸载确认（只提示一次）
 *   cmd|序号|动作|参数     —— report/msg/open/ku9/sh/reboot
 * 首次安装触发开机自启；/sdcard/tvbutler.conf 可覆盖 SRV= 与 POLL=。
 */
public class PollService extends Service {

    private HandlerThread thr;
    private Handler worker;          // 后台轮询
    private Handler main;            // Toast 用
    private android.content.SharedPreferences prefs;
    private volatile boolean running = false;

    /** UI 读取的状态 */
    public static volatile String STATUS = "启动中…";
    public static volatile long LAST_CHECK = 0;

    private class HandlerThread extends java.lang.Thread {
        public Handler h;
        public void run() {
            Looper.prepare();
            h = new Handler();
            worker = h;
            h.post(new Runnable() { public void run() { cycle(); } });
            Looper.loop();
        }
    }

    @Override
    public IBinder onBind(Intent i) { return null; }

    @Override
    public void onCreate() {
        super.onCreate();
        prefs = getSharedPreferences("butler", MODE_PRIVATE);
        main = new Handler(Looper.getMainLooper());
        Notification n = new Notification.Builder(this)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("TV管家")
                .setContentText("自动维护运行中")
                .setOngoing(true)
                .getNotification();
        startForeground(1, n);
        thr = new HandlerThread();
        thr.start();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "check_now".equals(intent.getAction()) && worker != null) {
            worker.post(new Runnable() { public void run() { cycle(); } });
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (worker != null) worker.getLooper().quit();
        super.onDestroy();
    }

    // ---------- 主循环 ----------

    private void cycle() {
        if (running) return; // 防重入
        running = true;
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        PowerManager.WakeLock wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "butler");
        try {
            wl.acquire(120000);
            check();
        } catch (Throwable t) {
            STATUS = "异常: " + t;
        } finally {
            try { wl.release(); } catch (Throwable t) { }
        }
        running = false;
        String[] conf = Util.conf(this);
        long ms = Long.parseLong(conf[1]) * 60000L;
        if (worker != null) worker.postDelayed(new Runnable() { public void run() { cycle(); } }, ms);
    }

    // ---------- 单轮检查 ----------

    private void check() {
        String[] conf = Util.conf(this);
        String srv = conf[0];

        StringBuilder u = new StringBuilder(srv).append("/cgi-bin/manifest")
                .append("?id=").append(Util.serial())
                .append("&mac=").append(Util.mac())
                .append("&sdk=").append(Util.sdk())
                .append("&model=").append(ue(Util.model()))
                .append("&up=").append(Util.upHours())
                .append("&mem=").append(Util.freeMem(this));

        String ta = Util.appList(this);
        if (ta.length() > 400) ta = ta.substring(0, 400);
        u.append("&tn=").append(ta.isEmpty() ? 0 : ta.split(",").length);
        u.append("&ta=").append(ue(ta));

        // 上一轮的指令回执（nonce:verb:res;...）
        String rc = prefs.getString("receipts", "");
        if (rc.length() > 0) u.append("&cmd=").append(ue(rc));

        STATUS = "正在联系服务器…";
        String text = Util.httpText(u.toString());
        LAST_CHECK = System.currentTimeMillis();
        if (text == null) {
            STATUS = "连接失败 " + now();
            return;
        }

        StringBuilder receipts = new StringBuilder();
        List<String> lines;
        try { lines = Util.readLinesFromString(text); }
        catch (Throwable t) { STATUS = "清单解析失败"; return; }

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] f = line.split("\\|");
            try {
                if ("install".equals(f[0]) && f.length >= 4) {
                    doInstall(f[1], f[2], f[3]);
                } else if ("remove".equals(f[0]) && f.length >= 2) {
                    doRemove(f[1]);
                } else if ("cmd".equals(f[0]) && f.length >= 3) {
                    String nonce = f[1], verb = f[2];
                    String arg = f.length > 3 ? f[3] : "";
                    String arg2 = f.length > 4 ? f[4] : "";
                    String res = doCmd(verb, arg, arg2, srv);
                    receipts.append(nonce).append(':').append(verb).append(':')
                            .append(res).append(';');
                }
            } catch (Throwable t) {
                STATUS = "处理异常: " + t;
            }
        }

        // 保存回执，下轮上报
        if (receipts.length() > 0) {
            prefs.edit().putString("receipts", receipts.toString()).commit();
        }
        STATUS = "正常 " + now();
    }

    private static String ue(String s) {
        try { return java.net.URLEncoder.encode(s, "UTF-8"); }
        catch (Throwable t) { return s == null ? "" : s; }
    }

    private static String now() {
        return new java.text.SimpleDateFormat("HH:mm", java.util.Locale.US)
                .format(new java.util.Date());
    }

    // ---------- install / remove ----------

    private void doInstall(String pkg, String md5, String url) {
        if (Util.installed(this, pkg)) return; // 已装
        if (md5 != null && md5.length() == 32 &&
                prefs.getString("prompted_" + md5, "").length() > 0) return; // 已提示过

        String dir = EnvironmentDir() + "/tvbutler/download";
        File out = new File(dir, pkg + ".apk");
        STATUS = "正在下载 " + pkg + "…";
        if (!Util.download(url, out.getAbsolutePath())) return;
        if (md5 != null && md5.length() == 32) {
            String got = Util.md5(out);
            if (!md5.equalsIgnoreCase(got)) { out.delete(); return; }
        }
        if (Util.hasRoot()) {
            String r = Util.suRun("pm install -r '" + out.getAbsolutePath() + "'");
            STATUS = "root 安装 " + pkg + ": " + r;
        } else {
            // 无 root：拉起系统安装器，客户按一次确认键
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(Uri.fromFile(out), "application/vnd.android.package-archive");
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { startActivity(i); } catch (Throwable t) { return; }
            if (md5 != null && md5.length() == 32)
                prefs.edit().putString("prompted_" + md5, "1").commit();
        }
    }

    private void doRemove(String pkg) {
        if (!Util.installed(this, pkg)) return;
        if (prefs.getString("removed_" + pkg, "").length() > 0) return;
        if (Util.hasRoot()) {
            Util.suRun("pm uninstall '" + pkg + "'");
        } else {
            Intent i = new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + pkg));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { startActivity(i); } catch (Throwable t) { return; }
            prefs.edit().putString("removed_" + pkg, "1").commit();
        }
    }

    // ---------- 指令 ----------

    private String doCmd(String verb, String arg, String arg2, String srv) {
        if ("report".equals(verb)) return "ok";
        if ("msg".equals(verb)) {
            toast(arg.isEmpty() ? "TV管家" : arg);
            return "ok";
        }
        if ("open".equals(verb)) {
            return launchApp(arg) ? "ok" : "fail";
        }
        if ("ku9".equals(verb)) {
            return deployKu9(srv) ? "ok" : "fail";
        }
        if ("reboot".equals(verb)) {
            if (Util.hasRoot()) { Util.suRun("reboot"); return "ok"; }
            return "noroot";
        }
        if ("sh".equals(verb)) {
            if (arg.isEmpty()) return "fail";
            // 无 root 且脚本是酷9部署脚本 → 用内置原生化部署等效完成
            if (!Util.hasRoot() && arg.contains("ku9-setup")) {
                return deployKu9(srv) ? "ok" : "fail";
            }
            if (!Util.hasRoot()) return "noroot";
            String path = EnvironmentDir() + "/tvbutler/rc.sh";
            if (!Util.download(arg, path)) return "dlfail";
            if (arg2 != null && arg2.length() == 32) {
                String got = Util.md5(new File(path));
                if (!arg2.equalsIgnoreCase(got)) return "md5fail";
            }
            return Util.suRun("sh '" + path + "'").startsWith("exit=0") ? "ok" : "fail";
        }
        return "skip";
    }

    private boolean launchApp(String pkg) {
        try {
            Intent i = getPackageManager().getLaunchIntentForPackage(pkg);
            if (i == null) return false;
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
            return true;
        } catch (Throwable t) { return false; }
    }

    private void toast(final String s) {
        main.post(new Runnable() { public void run() {
            Toast.makeText(PollService.this, s, Toast.LENGTH_LONG).show();
        }});
    }

    // ---------- 酷9 部署（无 root 版：写 /sdcard/酷9/ 三件套 + 拉起酷9） ----------

    private boolean deployKu9(String srv) {
        try {
            String base = EnvironmentDir() + "/酷9";
            String sn = Util.serial();
            boolean ok = true;

            // 大小写双份目录，兼容不同固件存储层
            String[][] dirs = { {"js", "JS"}, {"logo", "Logo"}, {"configuration", "Configuration"} };
            for (String[] d : dirs) {
                new File(base + "/" + d[0]).mkdirs();
                new File(base + "/" + d[1]).mkdirs();
            }

            ok &= Util.download(srv + "/ku9/quanzhou.js", base + "/js/quanzhou.js");
            copy(base + "/js/quanzhou.js", base + "/JS/quanzhou.js");
            ok &= Util.download(srv + "/ku9/epg_data.json", base + "/logo/epg_data.json");
            copy(base + "/logo/epg_data.json", base + "/Logo/epg_data.json");
            ok &= Util.download(srv + "/cgi-bin/admin?op=ku9cfg&sn=" + sn,
                    base + "/configuration/Configuration.json");
            copy(base + "/configuration/Configuration.json",
                    base + "/Configuration/Configuration.json");

            // 校验预置订阅字段确实写入
            File cfg = new File(base + "/configuration/Configuration.json");
            if (!cfg.isFile() || !new String(readFile(cfg), "UTF-8").contains("LIVE_URLS")) return false;
            if (!ok) return false;

            toast("酷9 配置部署完成");
            if (Util.installed(this, Util.KU9_PKG)) launchApp(Util.KU9_PKG);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    // ---------- 文件小工具 ----------

    private static String EnvironmentDir() {
        return android.os.Environment.getExternalStorageDirectory().getAbsolutePath();
    }

    private static void copy(String src, String dst) {
        try {
            java.io.InputStream in = new java.io.FileInputStream(src);
            java.io.OutputStream out = new java.io.FileOutputStream(dst);
            byte[] b = new byte[8192];
            int n;
            while ((n = in.read(b)) > 0) out.write(b, 0, n);
            in.close(); out.flush(); out.close();
        } catch (Throwable t) { }
    }

    private static byte[] readFile(File f) throws Exception {
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        java.io.InputStream in = new java.io.FileInputStream(f);
        byte[] b = new byte[8192];
        int n;
        while ((n = in.read(b)) > 0) bo.write(b, 0, n);
        in.close();
        return bo.toByteArray();
    }
}
