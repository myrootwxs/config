#!/bin/bash
# 根据 Git 提交记录按日整理工作日报
# 用法: ./daily_report.sh [today|yesterday|week|month|<YYYY-MM-DD>|<YYYY-MM-DD..YYYY-MM-DD>]

set -e

RANGE="${1:-week}"
NOW=$(date '+%Y-%m-%d')
AUTHOR="${GIT_AUTHOR:-$(git config user.name 2>/dev/null || echo '')}"

case "$RANGE" in
    today)
        SINCE="$NOW"
        UNTIL="$NOW"
        ;;
    yesterday)
        SINCE=$(date -d 'yesterday' '+%Y-%m-%d')
        UNTIL="$SINCE"
        ;;
    week)
        # 本周一到今天
        DAY_OF_WEEK=$(date '+%u')
        SINCE=$(date -d "$NOW - $((DAY_OF_WEEK - 1)) days" '+%Y-%m-%d')
        UNTIL="$NOW"
        ;;
    month)
        SINCE=$(date '+%Y-%m-01')
        UNTIL="$NOW"
        ;;
    *..*)
        SINCE="${RANGE%%..*}"
        UNTIL="${RANGE##*..}"
        ;;
    *)
        # 单天
        SINCE="$RANGE"
        UNTIL="$RANGE"
        ;;
esac

# 构建 git log 参数
GIT_ARGS="--since=${SINCE}T00:00:00 --until=${UNTIL}T23:59:59"
if [ -n "$AUTHOR" ]; then
    GIT_ARGS="$GIT_ARGS --author=$AUTHOR"
fi

# 获取提交并按天分组
echo "时间范围: $SINCE ~ $UNTIL"
echo ""

# 使用 git log 获取所有提交，输出格式: YYYY-MM-DD|hash|HH:MM|subject
COMMITS=$(git log $GIT_ARGS --format='%ad|%h|%s' --date=format:'%Y-%m-%d %H:%M' --reverse 2>/dev/null || echo "")

if [ -z "$COMMITS" ]; then
    echo "该时间范围内无提交记录。"
    exit 0
fi

# 按日期分组输出
PREV_DATE=""
# 星期映射
declare -A WEEKDAYS=(
    ["Monday"]="周一" ["Tuesday"]="周二" ["Wednesday"]="周三"
    ["Thursday"]="周四" ["Friday"]="周五" ["Saturday"]="周六" ["Sunday"]="周日"
)

while IFS='|' read -r datetime hash subject; do
    date="${datetime:0:10}"
    time="${datetime:11:5}"
    if [ "$date" != "$PREV_DATE" ]; then
        WEEKDAY=$(date -d "$date" '+%A' 2>/dev/null || echo "")
        WEEKDAY_CN="${WEEKDAYS[$WEEKDAY]:-$WEEKDAY}"
        echo ""
        echo "## ${date}（${WEEKDAY_CN}）"
        PREV_DATE="$date"
    fi
    echo ""
    # 将 subject 按 " [" 拆分，每个 [标签] 独立一行
    # 先拆出时间段，再对每个标签块缩进输出
    # 将 subject 拆分为多行：第一个标签跟时间同行，后续标签缩进换行
    tag_count=$(echo "$subject" | grep -o '\[[^]]*\]' | wc -l)
    if [ "$tag_count" -gt 1 ]; then
        first_line=$(echo "$subject" | sed -E 's/ \[/\n  [/g')
        echo "**\`$hash\`** ${time} ${first_line}"
    else
        echo "**\`$hash\`** ${time} $subject"
    fi
done <<< "$COMMITS"
