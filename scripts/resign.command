#!/bin/bash
# 换机 / 系统重装后用：从备份的 .p12 恢复签名证书，再重新构建安装。
# 用法：双击运行（默认读同目录上层的 ClickPulse-signing.p12），或在终端传路径：
#   ./resign.command /path/to/ClickPulse-signing.p12
set -euo pipefail
cd "$(dirname "$0")/.."

P12="${1:-ClickPulse-signing.p12}"
if [ ! -f "$P12" ]; then
  echo "❌ 找不到证书备份：$P12"
  echo "   请把当初导出的 ClickPulse-signing.p12 放到项目根目录，或作为参数传入路径。"
  exit 1
fi

echo "==> 从 $P12 导入签名证书到登录钥匙串（可能提示输入 .p12 密码）"
security import "$P12" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign

echo "==> 重新构建 + 签名 + 安装"
exec scripts/build.command
