package com.tvupd.butler;

import android.app.Application;

/** 全局 Application：提供单例 Context 给 Util 的静态方法用 */
public class App extends Application {
    private static App sInst;
    @Override
    public void onCreate() {
        super.onCreate();
        sInst = this;
    }
    public static App inst() { return sInst; }
}
