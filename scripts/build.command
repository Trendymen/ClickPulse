#!/bin/bash
# ClickPulse 一键构建 + 签名 + 安装到 /Applications
# 双击运行即可。依赖 Xcode、XcodeGen、钥匙串里名为 "ClickPulse Self-Signed" 的代码签名证书。
set -euo pipefail
cd "$(dirname "$0")/.."

CERT="ClickPulse Self-Signed"
APP="/Applications/ClickPulse.app"

echo "==> 检查签名证书"
if ! security find-identity -p codesigning | grep -q "${CERT}"; then
  echo "找不到代码签名证书: ${CERT}"
  echo "请先在 钥匙串访问 > 证书助理 > 创建证书 建一个名为 ${CERT} 的 Code Signing 自签名证书。"
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译 Release 并用固定证书签名"
xcodebuild -project ClickPulse.xcodeproj -scheme ClickPulse -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="${CERT}" CODE_SIGN_STYLE=Manual -quiet

BUILT="build/Build/Products/Release/ClickPulse.app"
if [ ! -d "${BUILT}" ]; then echo "未找到构建产物: ${BUILT}"; exit 1; fi

echo "==> 安装到 /Applications"
rm -rf "${APP}"
cp -R "${BUILT}" "${APP}"
xattr -dr com.apple.quarantine "${APP}" 2>/dev/null || true

echo ""
echo "完成: ${APP}"
echo "签名身份: ${CERT}"
echo "首次运行后请到 系统设置 > 隐私与安全性 > 输入监控 勾选 ClickPulse"
open "${APP}"
