#!/usr/bin/env bash
# Claude Code 配置一键恢复脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CLAUDE="${SCRIPT_DIR}/.claude"
TARGET_CLAUDE="${HOME}/.claude"
TARGET_AGENTS="${HOME}/.agents"

echo "=========================================="
echo "      Claude Code 配置一键恢复工具         "
echo "=========================================="

if [ ! -d "${SOURCE_CLAUDE}" ]; then
    echo "错误: 未在当前仓库找到 .claude 目录: ${SOURCE_CLAUDE}"
    exit 1
fi

# 1. 确保目标目录存在
mkdir -p "${TARGET_CLAUDE}"
mkdir -p "${TARGET_AGENTS}"

# 2. 赋予脚本执行权限
chmod +x "${SOURCE_CLAUDE}/statusline-command.sh" 2>/dev/null || true

echo "正在同步配置文件到 ${TARGET_CLAUDE} ..."

# 3. 复制核心配置与规则
cp -a "${SOURCE_CLAUDE}/CLAUDE.md" "${TARGET_CLAUDE}/"
cp -a "${SOURCE_CLAUDE}/statusline-command.sh" "${TARGET_CLAUDE}/"
[ -f "${SOURCE_CLAUDE}/config.json" ] && cp -a "${SOURCE_CLAUDE}/config.json" "${TARGET_CLAUDE}/"
[ -f "${SOURCE_CLAUDE}/.mcp.json" ] && cp -a "${SOURCE_CLAUDE}/.mcp.json" "${TARGET_CLAUDE}/"

# 复制 rules
if [ -d "${SOURCE_CLAUDE}/rules" ]; then
    mkdir -p "${TARGET_CLAUDE}/rules"
    cp -a "${SOURCE_CLAUDE}/rules/"* "${TARGET_CLAUDE}/rules/"
fi

# 4. 恢复通用 skills：同时支持 ~/.claude/skills 和 ~/.agents/skills
if [ -d "${SOURCE_CLAUDE}/skills" ]; then
    echo "正在恢复通用 skills ..."
    mkdir -p "${TARGET_AGENTS}/skills"
    cp -a "${SOURCE_CLAUDE}/skills/"* "${TARGET_AGENTS}/skills/"
    # 建立软链接 ~/.claude/skills -> ~/.agents/skills（若尚未建立）
    if [ ! -L "${TARGET_CLAUDE}/skills" ]; then
        rm -rf "${TARGET_CLAUDE}/skills"
        ln -s "${TARGET_AGENTS}/skills" "${TARGET_CLAUDE}/skills"
    fi
fi

# 5. 复制 settings 预设文件
for f in "${SOURCE_CLAUDE}"/settings*.json; do
    [ -f "$f" ] && cp -a "$f" "${TARGET_CLAUDE}/"
done

# 6. 配置 ANTHROPIC_AUTH_TOKEN
echo ""
echo "------------------------------------------"
echo "Token 配置检查"
echo "------------------------------------------"

CURRENT_TOKEN=""
if [ -n "${ANTHROPIC_AUTH_TOKEN}" ]; then
    CURRENT_TOKEN="${ANTHROPIC_AUTH_TOKEN}"
    echo "检测到环境变量 \$ANTHROPIC_AUTH_TOKEN 已设置。"
fi

if [ -f "${TARGET_CLAUDE}/settings.json" ]; then
    TOKEN_IN_FILE=$(grep -o '"ANTHROPIC_AUTH_TOKEN": "[^"]*"' "${TARGET_CLAUDE}/settings.json" | cut -d'"' -f4 || true)
    if [ "$TOKEN_IN_FILE" = "YOUR_ANTHROPIC_AUTH_TOKEN" ]; then
        if [ -n "$CURRENT_TOKEN" ]; then
            sed -i "s/YOUR_ANTHROPIC_AUTH_TOKEN/${CURRENT_TOKEN}/g" "${TARGET_CLAUDE}/settings"*.json
            echo "已自动使用环境变量中的 Token 替换配置中的占位符！"
        else
            echo "提示: 当前 settings.json 中的 ANTHROPIC_AUTH_TOKEN 为占位符。"
            echo "可在之后手动编辑 ~/.claude/settings.json 或直接 export ANTHROPIC_AUTH_TOKEN=..."
        fi
    else
        echo "settings.json 中的 Token 已就绪。"
    fi
fi

echo ""
echo "=========================================="
echo "配置恢复完成！"
echo "位置: ${TARGET_CLAUDE}"
echo "包含: 状态栏脚本, 规则 (rules), 通用技能 (skills), 预设配置等"
echo "=========================================="
