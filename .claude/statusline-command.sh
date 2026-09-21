#!/bin/bash
# ---------------------------------------------------------------------------
# 状态栏脚本
# 显示：模型 | 思考强度 | 上下文使用量 | 上下文窗口占比 | 模型输出速度
# 输入：stdin 传入的会话 JSON，输出速度由 transcript_path 会话记录推算
# ---------------------------------------------------------------------------

# Catppuccin Mocha 配色（状态栏以暗色渲染，故取亮色相）
C_RESET=$'\033[0m'
C_DIM=$'\033[2m'
C_MODEL=$'\033[38;2;180;190;254m'  # lavender
C_EFFORT=$'\033[38;2;203;166;247m' # mauve
C_OK=$'\033[38;2;166;227;161m'     # green
C_WARN=$'\033[38;2;249;226;175m'   # yellow
C_BAD=$'\033[38;2;243;139;168m'    # red
C_CTX=$'\033[38;2;137;180;250m'    # blue
C_SPEED=$'\033[38;2;148;226;213m'  # teal

input=$(cat)

# 一次性取出所需字段；逐行输出后用 mapfile 读取，
# 避免 IFS 分隔时「空白分隔符折叠」导致空字段错位。
mapfile -t f < <(
    printf '%s' "$input" | jq -r '[
        (.model.display_name // .model.id // "?"),
        (.effort.level // ""),
        (.thinking.enabled // false | tostring),
        (.context_window.total_input_tokens // "" | tostring),
        (.context_window.used_percentage // "" | tostring),
        (.context_window.context_window_size // "" | tostring),
        (.transcript_path // "")
    ] | .[]' 2>/dev/null
)

model=${f[0]:-}
effort=${f[1]:-}
thinking=${f[2]:-}
used=${f[3]:-}
pct=${f[4]:-}
size=${f[5]:-}
transcript=${f[6]:-}
model=${model:-"?"}

# ---------- 输出速度 ----------
# 取最近一条 assistant 消息的 output_tokens，除以「它之前最近一条记录 → 该消息」的
# 时间差，得到该次生成的近似吐字速率（tok/s）。为避免只含工具调用的短消息导致数值
# 抖动，优先采用 output_tokens >= 50 的样本，否则退化为最近一条可用样本。
speed=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    speed=$(tail -n 400 "$transcript" 2>/dev/null | jq -Rrs '
        # 时间戳归一化：去掉毫秒与时区偏移后按 UTC 解析（同一文件偏移一致，差值不受影响）
        def epoch:
            ((. // "")
             | sub("\\.[0-9]+"; "")
             | sub("[+-][0-9]{2}:[0-9]{2}$"; "Z")
             | fromdateiso8601? // null);
        (split("\n") | map(select(length > 0) | (fromjson? // empty))) as $e
        | ($e | length) as $n
        | [ range(0; $n)
            | . as $i
            | $e[$i] as $rec
            | select($rec.type == "assistant")
            | ($rec.message.usage.output_tokens // $rec.usage.output_tokens // 0) as $tok
            | select($tok > 0)
            | ([ range(0; $i) | ($e[.].timestamp | epoch) | select(. != null) ] | last) as $t0
            | ($rec.timestamp | epoch) as $t1
            | select(($t0 != null) and ($t1 != null) and (($t1 - $t0) >= 0.5))
            | { tokens: $tok, dt: ($t1 - $t0) }
          ] as $cand
        | (($cand | map(select(.tokens >= 50)) | last) // ($cand | last))
        | select(. != null)
        | (.tokens / .dt)
    ' 2>/dev/null)
fi

# ---------- 数值格式化：千级转 k、百万级转 M ----------
num_fmt() {
    awk -v n="$1" 'BEGIN {
        if (n >= 1000000)   printf "%.1fM", n / 1000000;
        else if (n >= 1000) printf "%.1fk", n / 1000;
        else                printf "%d", n;
    }'
}

line=""
add_part() { # 以暗色竖线拼接各显示段
    if [ -n "$line" ]; then
        line="$line${C_DIM} │ ${C_RESET}"
    fi
    line="$line$1"
}

# 1. 当前模型
add_part "${C_MODEL}${model}${C_RESET}"

# 2. 思考强度（无 effort 字段时退化为 thinking 开关状态）
if [ -n "$effort" ]; then
    add_part "${C_EFFORT}effort:${effort}${C_RESET}"
elif [ "$thinking" = "true" ]; then
    add_part "${C_EFFORT}think:on${C_RESET}"
else
    add_part "${C_EFFORT}think:off${C_RESET}"
fi

# 3. 上下文使用量
if [ -n "$used" ]; then
    if [ -n "$size" ]; then
        add_part "${C_CTX}ctx $(num_fmt "$used")/$(num_fmt "$size")${C_RESET}"
    else
        add_part "${C_CTX}ctx $(num_fmt "$used")${C_RESET}"
    fi
fi

# 4. 上下文窗口占比（越高越危险：<50 绿、<80 黄、>=80 红）
if [ -n "$pct" ]; then
    pct_int=$(printf '%.0f' "$pct" 2>/dev/null)
    if [ -n "$pct_int" ]; then
        if [ "$pct_int" -ge 80 ] 2>/dev/null; then
            pct_color=$C_BAD
        elif [ "$pct_int" -ge 50 ] 2>/dev/null; then
            pct_color=$C_WARN
        else
            pct_color=$C_OK
        fi
        add_part "${pct_color}${pct_int}%${C_RESET}"
    fi
fi

# 5. 模型输出速度
if [ -n "$speed" ]; then
    add_part "${C_SPEED}$(printf '%.1f' "$speed" 2>/dev/null) tok/s${C_RESET}"
else
    add_part "${C_DIM}-- tok/s${C_RESET}"
fi

printf '%s' "$line"
