package com.tvupd.butler;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.app.ActivityManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.List;

/** 工具集：服务器地址/参数、下载、md5、序列号/MAC/应用清单、root 探测与 su 执行 */
public final class Util {

    /** 默认分发服务器（可用 /sdcard/tvbutler.conf 里 SRV= 行覆盖） */
    public static final String DEF_SRV = "http://your.domain:8083";
    public static final int DEF_POLL_MIN = 10;
    public static final String PKG = "com.tvupd.butler";
    public static final String KU9_PKG = "com.player.ku9lite";

    private Util() {}

    /** 读 /sdcard/tvbutler.conf（SRV= / POLL= 行），返回当前生效值 */
    public static String[] conf(Context c) {
        String srv = c.getSharedPreferences("butler", Context.MODE_PRIVATE)
                .getString("srv", DEF_SRV);
        int poll = c.getSharedPreferences("butler", Context.MODE_PRIVATE)
                .getInt("poll", DEF_POLL_MIN);
        try {
            File f = new File(Environment.getExternalStorageDirectory(), "tvbutler.conf");
            if (f.isFile()) {
                List<String> lines = readLines(f.getAbsolutePath());
                for (String l : lines) {
                    l = l.trim();
                    if (l.startsWith("SRV=") && l.length() > 4) srv = l.substring(4).trim();
                    else if (l.startsWith("POLL=")) poll = Integer.parseInt(l.substring(5).trim());
                }
            }
        } catch (Throwable t) { }
        if (poll < 1) poll = DEF_POLL_MIN;
        return new String[]{srv, String.valueOf(poll)};
    }

    public static String serial() {
        String s = Build.SERIAL;
        if (s == null || s.length() == 0 || "unknown".equals(s)) {
            s = prop("ro.serialno");
        }
        return (s == null || s.length() == 0) ? "unknown" : s;
    }

    public static String prop(String k) {
        try {
            Class<?> sp = Class.forName("android.os.SystemProperties");
            return (String) sp.getMethod("get", String.class).invoke(null, k);
        } catch (Throwable t) { return ""; }
    }

    public static String mac() {
        try {
            List<String> l = readLines("/sys/class/net/wlan0/address");
            if (!l.isEmpty()) return l.get(0).trim().replace(":", "").toLowerCase();
        } catch (Throwable t) { }
        try {
            WifiManager w = (WifiManager) getSystemServiceApp(WifiManager.class);
            if (w != null) {
                String m = w.getConnectionInfo().getMacAddress();
                if (m != null) return m.replace(":", "").toLowerCase();
            }
        } catch (Throwable t) { }
        return "000000000000";
    }

    private static Object getSystemServiceApp(Class<?> cls) {
        try {
            return App.inst().getSystemService(cls.getName());
        } catch (Throwable t) { return null; }
    }

    public static String model() { return Build.MODEL == null ? "-" : Build.MODEL; }

    public static int sdk() { return Build.VERSION.SDK_INT; }

    /** 已装应用包名清单（含自己），逗号分隔 */
    public static String appList(Context c) {
        StringBuilder sb = new StringBuilder();
        try {
            PackageManager pm = c.getPackageManager();
            List<ApplicationInfo> all = pm.getInstalledApplications(0);
            for (ApplicationInfo ai : all) {
                if (sb.length() > 0) sb.append(',');
                sb.append(ai.packageName);
            }
        } catch (Throwable t) { }
        return sb.toString();
    }

    public static boolean installed(Context c, String pkg) {
        try {
            c.getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (Throwable t) { return false; }
    }

    /** 可用内存 MB */
    public static long freeMem(Context c) {
        try {
            ActivityManager am = (ActivityManager) c.getSystemService(Context.ACTIVITY_SERVICE);
            ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
            am.getMemoryInfo(mi);
            return mi.availMem / 1048576L;
        } catch (Throwable t) { return -1; }
    }

    /** 开机时长（小时） */
    public static long upHours() {
        return android.os.SystemClock.elapsedRealtime() / 3600000L;
    }

    // ---- 网络 ----

    /** 下载到文件；返回是否成功且非空 */
    public static boolean download(String url, String out) {
        FileOutputStream fo = null;
        try {
            byte[] data = httpGet(url, 30000);
            if (data == null || data.length == 0) return false;
            File f = new File(out);
            f.getParentFile().mkdirs();
            fo = new FileOutputStream(f);
            fo.write(data);
            fo.flush();
            return true;
        } catch (Throwable t) {
            return false;
        } finally {
            try { if (fo != null) fo.close(); } catch (Throwable t) { }
        }
    }

    /** 下载到字符串；失败返回 null */
    public static String httpText(String url) {
        try {
            byte[] d = httpGet(url, 20000);
            if (d == null) return null;
            return new String(d, "UTF-8");
        } catch (Throwable t) { return null; }
    }

    static byte[] httpGet(String u, int timeoutMs) throws Exception {
        HttpURLConnection hc = (HttpURLConnection) new URL(u).openConnection();
        hc.setConnectTimeout(timeoutMs);
        hc.setReadTimeout(timeoutMs);
        hc.setRequestMethod("GET");
        int code = hc.getResponseCode();
        if (code != 200) { hc.disconnect(); return null; }
        InputStream is = hc.getInputStream();
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = is.read(buf)) > 0) bo.write(buf, 0, n);
        is.close();
        hc.disconnect();
        return bo.toByteArray();
    }

    public static String md5(File f) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            InputStream is = new java.io.FileInputStream(f);
            byte[] buf = new byte[8192];
            int n;
            while ((n = is.read(buf)) > 0) md.update(buf, 0, n);
            is.close();
            byte[] d = md.digest();
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Throwable t) { return ""; }
    }

    public static java.util.List<String> readLines(String path) throws Exception {
        java.util.List<String> out = new java.util.ArrayList<String>();
        BufferedReader br = new BufferedReader(new InputStreamReader(
                new java.io.FileInputStream(path), "UTF-8"));
        String l;
        while ((l = br.readLine()) != null) out.add(l);
        br.close();
        return out;
    }

    public static java.util.List<String> readLinesFromString(String s) {
        java.util.List<String> out = new java.util.ArrayList<String>();
        try {
            BufferedReader br = new BufferedReader(new InputStreamReader(
                    new java.io.ByteArrayInputStream(s.getBytes()), "UTF-8"));
            String l;
            while ((l = br.readLine()) != null) out.add(l);
            br.close();
        } catch (Throwable t) { }
        return out;
    }

    /** 读小文件全部字节（UI 侧校验用） */
    public static byte[] readFilePub(File f) throws Exception {
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        InputStream in = new java.io.FileInputStream(f);
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        in.close();
        return bo.toByteArray();
    }

    // ---- root ----

    private static Boolean ROOT = null;

    /** 探测 su 是否可用（结果缓存） */
    public static boolean hasRoot() {
        if (ROOT != null) return ROOT.booleanValue();
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(new String[]{"su", "-c", "id"});
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line = br.readLine();
            br.close();
            int exit = p.waitFor();
            ROOT = Boolean.valueOf(exit == 0 && line != null && line.contains("uid=0"));
        } catch (Throwable t) {
            ROOT = Boolean.FALSE;
        } finally {
            if (p != null) p.destroy();
        }
        return ROOT.booleanValue();
    }

    /** 以 root 执行命令；返回输出+退出码文本 */
    public static String suRun(String cmd) {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"su", "-c", cmd});
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String l;
            while ((l = br.readLine()) != null) sb.append(l).append('\n');
            br.close();
            int code = p.waitFor();
            return "exit=" + code + " " + sb.toString().trim();
        } catch (Throwable t) {
            return "err " + t;
        }
    }
}
