#!/system/bin/sh
setprop service.adb.tcp.port 5555
stop adbd
start adbd
sleep 2
getprop service.adb.tcp.port
