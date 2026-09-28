#!/bin/bash
# TV管家 APK（agent） 构建脚本（与 tvbox-apk 同款工具链：JDK17 + build-tools r34 + API19/35 jar）
# 用法: bash "I:/5566game/2026-09-28-18-10-03/tvbutler/build.sh"
set -e

JDK="C:/Program Files/Microsoft/jdk-17.0.16.8-hotspot/bin"
BT="I:/workbuddy/android-sdk/android-14"
AJ="I:/workbuddy/android-sdk/android-19.jar"           # 编译用（API19，防误用新 API）
RES="I:/workbuddy/android-sdk/android-35/android.jar"  # aapt2 用（含框架资源定义）
ROOT="I:/5566game/2026-09-28-18-10-03/tvbutler"

cd "$ROOT"
mkdir -p build/classes build/dex out
rm -f build/classes/*.class build/dex/* build/base.apk build/aligned.apk

echo "== 1/7 javac =="
# robolectric android-all 不含 java.*：不能用 -bootclasspath，只用 -cp，java.* 走 JDK 自身
"$JDK/javac.exe" -encoding UTF-8 -source 8 -target 8 -nowarn \
  -cp "$AJ" \
  -d build/classes src/com/tvupd/butler/*.java

echo "== 2/7 d8 =="
rm -f build/classes.jar
"$JDK/jar.exe" cf build/classes.jar -C build/classes .
"$JDK/java.exe" -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 \
  --min-api 19 --lib "$AJ" --output build/dex build/classes.jar

echo "== 3/7 aapt2 link =="
"$BT/aapt2.exe" link -I "$RES" \
  --manifest AndroidManifest.xml \
  --min-sdk-version 19 --target-sdk-version 19 \
  -o build/base.apk

echo "== 4/7 打包 classes.dex =="
# -M：不生成 META-INF/MANIFEST.MF（会干扰 V1 签名）
"$JDK/jar.exe" ufM build/base.apk -C build/dex classes.dex

echo "== 5/7 zipalign =="
"$BT/zipalign.exe" -p -f 4 build/base.apk build/aligned.apk

echo "== 6/7 签名 =="
# 不用 jarsigner（JDK17 禁 SHA1 → 4.4 判未签名）。
# apksigner min-sdk 17 → V1 用 SHA1 摘要；只出 V1，Android 4.4 需要。
if [ ! -f tvbutler.jks ]; then
  "$JDK/keytool.exe" -genkeypair -alias tvbutler -keyalg RSA -keysize 2048 \
    -validity 10950 -keystore tvbutler.jks -storepass tvbutler -keypass tvbutler \
    -dname "CN=tvbutler, OU=darst, O=darst, L=CN, ST=CN, C=CN" \
    -sigalg SHA256withRSA
fi
rm -f out/tv-butler.apk
"$JDK/java.exe" -cp "$BT/lib/apksigner.jar" com.android.apksigner.ApkSignerTool sign \
  --ks tvbutler.jks --ks-key-alias tvbutler \
  --ks-pass pass:tvbutler --key-pass pass:tvbutler \
  --min-sdk-version 17 \
  --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
  --out out/tv-butler.apk build/aligned.apk

echo "== 7/7 校验 =="
"$BT/aapt2.exe" dump badging out/tv-butler.apk | head -5
echo
echo "产物: $ROOT/out/tv-butler.apk"
