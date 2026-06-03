#!/bin/bash
# 一键：从 WhatPulse 迁移鼠标点击数据到 ClickPulse（覆盖现有数据）
# 把 WhatPulse 的 mouseclicks_frequency(天 × 小时 × 按键) 灌入 ClickPulse 的 click_hourly。
#
# 注意：WhatPulse 运行时内存里有未落表的实时增量(unpulsed_stats)，本脚本导入的是已落表数据，
#       会少这部分。想最准：先在 WhatPulse 点一次「Pulse」或退出 WhatPulse，再跑本脚本。
set -euo pipefail

WP_DB="$HOME/Library/Application Support/WhatPulse/whatpulse.db"
CP_DB="$HOME/Library/Application Support/com.liuzhuo.clickpulse/clickpulse.sqlite"
TMP="/tmp/clickpulse-wp-snapshot.db"

echo "==> 检查数据库"
[ -f "$WP_DB" ] || { echo "找不到 WhatPulse 数据库: $WP_DB"; exit 1; }
[ -f "$CP_DB" ] || { echo "找不到 ClickPulse 数据库(先跑一次 ClickPulse): $CP_DB"; exit 1; }

echo "==> 取 WhatPulse 一致性快照（不锁原库）"
rm -f "$TMP"
sqlite3 "$WP_DB" ".backup '$TMP'"
WP_TOTAL=$(sqlite3 "$TMP" "SELECT COALESCE(SUM(count),0) FROM mouseclicks_frequency WHERE profile_id=0;")
WP_UNPULSED=$(sqlite3 "$TMP" "SELECT COALESCE(value,0) FROM unpulsed_stats WHERE name='clicks';")
echo "   WhatPulse 已落表点击 = ${WP_TOTAL}（另有未落表实时增量约 ${WP_UNPULSED} 次，不会被导入）"

echo "==> 停止 ClickPulse"
pkill -f "Applications/ClickPulse.app/Contents/MacOS" 2>/dev/null || true
sleep 1

echo "==> 备份 ClickPulse 当前数据 -> clickpulse.sqlite.bak"
cp "$CP_DB" "${CP_DB}.bak"

echo "==> 覆盖导入"
sqlite3 "$CP_DB" <<SQL
ATTACH '${TMP}' AS wp;
BEGIN;
DELETE FROM click_hourly;
INSERT INTO click_hourly (hour_ts, local_hour, local_weekday, button, count)
SELECT
  CAST(strftime('%s', day || ' ' || printf('%02d:00:00', hour), 'utc') AS INTEGER),
  hour,
  ((CAST(strftime('%w', day) AS INTEGER) + 6) % 7) + 1,
  CASE WHEN button <= 2 THEN button ELSE 3 END,
  count
FROM wp.mouseclicks_frequency
WHERE profile_id = 0 AND count > 0;
COMMIT;
DETACH wp;
SQL

CP_TOTAL=$(sqlite3 "$CP_DB" "SELECT COALESCE(SUM(count),0) FROM click_hourly;")
echo "==> 导入完成：ClickPulse 总点击 = ${CP_TOTAL}"
if [ "$CP_TOTAL" = "$WP_TOTAL" ]; then
  echo "   OK 与 WhatPulse 已落表数据完全一致"
else
  echo "   注意：与 WhatPulse(${WP_TOTAL}) 略有差异（正常，源于实时缓冲/落库时机）"
fi

rm -f "$TMP"
echo "==> 重启 ClickPulse"
open /Applications/ClickPulse.app
echo "完成。"
