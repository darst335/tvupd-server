#!/bin/bash
# TV管家 APK（agent） 构建脚本（JDK17 + build-tools r34 + API19/35 平台 jar）
#
# 用法:
#   bash build.sh
#
# ★ 工具链路径全部用环境变量覆盖，脚本里不写死任何机器的盘符：
#   JDK=…  JDK17 的 bin 目录          （缺省：取 PATH 里 javac 所在目录）
#   BT=…   Android build-tools 目录   （缺省：取 PATH 里 aapt2 所在目录）
#   SDK=…  Android SDK 根目录         （缺省：BT 的上一级；用来找 platforms/）
#   AJ=…   编译用平台 jar（API19；它不含 java.*，只能放 -cp，不能当 -bootclasspath）
#   RES=…  aapt2 用的平台 jar（要真 SDK 平台包，API35+；robolectric 的不含框架资源定义）
#   KS_PASS=…  签名 keystore 口令（缺省 tvbutler，仅调试用；正式发布务必改掉并自己保管 .jks）
#
# Windows 下会自动尝试 .exe 后缀。
set -e

exe() { if [ -x "$1" ]; then echo "$1"; elif [ -x "$1.exe" ]; then echo "$1.exe"; else echo "$1"; fi; }

JDK="${JDK:-$(dirname "$(command -v javac)")}"
BT="${BT:-$(dirname "$(command -v aapt2)")}"
if [ -z "${AJ:-}" ] || [ -z "${RES:-}" ]; then
    SDK="${SDK:-$(dirname "$BT")}"
    [ -n "${AJ:-}" ]  || AJ="$(ls "$SDK"/platforms/android-19/android.jar 2>/dev/null | head -n1)"
    [ -n "${RES:-}" ] || RES="$(ls -r "$SDK"/platforms/android-*/android.jar 2>/dev/null | head -n1)"
fi

MISS=""
for v in JDK BT AJ RES; do
    eval p="\${$v-}"
    if [ -z "$p" ] || [ ! -e "$p" ]; then MISS="$MISS $v"; fi
done
if [ -n "$MISS" ]; then
    echo "!! 找不到工具链:$MISS" >&2
    echo "   请用环境变量指定，例如:" >&2
    echo "   JDK='/path/jdk17/bin' BT='/path/build-tools/34.0.0' SDK='/path/android-sdk' bash build.sh" >&2
    exit 1
fi
echo "工具链: JDK=$JDK"
echo "        BT=$BT"
echo "        AJ=$AJ"
echo "        RES=$RES"

# 项目根 = 本脚本所在目录（src/ AndroidManifest.xml 都在这下面）
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

KS_PASS="${KS_PASS:-tvbutler}"

mkdir -p build/classes build/dex out
rm -f build/classes/*.class build/dex/* build/base.apk build/aligned.apk

echo "== 1/7 javac =="
# API19 平台 jar 不含 java.*：不能用 -bootclasspath，只用 -cp，java.* 走 JDK 自身
"$(exe "$JDK/javac")" -encoding UTF-8 -source 8 -target 8 -nowarn \
  -cp "$AJ" \
  -d build/classes src/com/tvupd/butler/*.java

echo "== 2/7 d8 =="
rm -f build/classes.jar
"$(exe "$JDK/jar")" cf build/classes.jar -C build/classes .
"$(exe "$JDK/java")" -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 \
  --min-api 19 --lib "$AJ" --output build/dex build/classes.jar

echo "== 3/7 aapt2 link =="
"$(exe "$BT/aapt2")" link -I "$RES" \
  --manifest AndroidManifest.xml \
  --min-sdk-version 19 --target-sdk-version 19 \
  -o build/base.apk

echo "== 4/7 打包 classes.dex =="
# -M：不生成 META-INF/MANIFEST.MF（会干扰 V1 签名）
"$(exe "$JDK/jar")" ufM build/base.apk -C build/dex classes.dex

echo "== 5/7 zipalign =="
"$(exe "$BT/zipalign")" -p -f 4 build/base.apk build/aligned.apk

echo "== 6/7 签名 =="
# 不用 jarsigner（JDK17 禁 SHA1 → 4.4 判未签名）。
# apksigner min-sdk 17 → V1 用 SHA1 摘要；只出 V1，Android 4.4 需要。
# ★ 本地调试 keystore，脚本首次运行自动生成；正式发布请用自己的 .jks 并覆盖 KS_PASS。
if [ ! -f tvbutler.jks ]; then
  "$(exe "$JDK/keytool")" -genkeypair -alias tvbutler -keyalg RSA -keysize 2048 \
    -validity 10950 -keystore tvbutler.jks -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -dname "CN=tvbutler" \
    -sigalg SHA256withRSA
fi
rm -f out/tv-butler.apk
"$(exe "$JDK/java")" -cp "$BT/lib/apksigner.jar" com.android.apksigner.ApkSignerTool sign \
  --ks tvbutler.jks --ks-key-alias tvbutler \
  --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
  --min-sdk-version 17 \
  --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
  --out out/tv-butler.apk build/aligned.apk

echo "== 7/7 校验 =="
"$(exe "$BT/aapt2")" dump badging out/tv-butler.apk | head -5
echo
echo "产物: $ROOT/out/tv-butler.apk"
