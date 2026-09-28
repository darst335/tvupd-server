package com.tvupd.butler;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** 开机自启：启动轮询服务（Android 4.4 对普通 app 的 BOOT_COMPLETED 无限制） */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            context.startService(new Intent(context, PollService.class));
        }
    }
}
