#!/usr/bin/env bash
# Claude Code 配置一键安装与恢复脚本（支持本地执行与 curl | bash 管道直接执行）
set -e

echo "=========================================="
echo "      Claude Code 配置一键安装工具         "
echo "=========================================="

REPO_SLUG="myrootwxs/config"
TARGET_CLAUDE="${HOME}/.claude"
TEMP_DIR=""

# 退出时自动清理临时目录
cleanup() {
    if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

# 检查当前路径是否已有 .claude 目录
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
fi

SOURCE_CLAUDE=""
if [ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/.claude" ]; then
    SOURCE_CLAUDE="${SCRIPT_DIR}/.claude"
    echo "使用本地配置文件: ${SOURCE_CLAUDE}"
elif [ -d "./.claude" ]; then
    SOURCE_CLAUDE="$(pwd)/.claude"
    echo "使用当前目录配置文件: ${SOURCE_CLAUDE}"
else
    echo "未在本地检测到 .claude 目录，正在从 GitHub (${REPO_SLUG}) 下载最新配置..."
    TEMP_DIR="$(mktemp -d)"

    # 优先直接使用 curl 下载公开仓库归档（极快且无需 git 环境）
    if curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/tarball/main" | tar -xz -C "${TEMP_DIR}" --strip-components=1 2>/dev/null; then
        SOURCE_CLAUDE="${TEMP_DIR}/.claude"
    # 若 API 请求受限，回退使用 git clone
    elif git clone --depth=1 "https://github.com/${REPO_SLUG}.git" "${TEMP_DIR}/repo" 2>/dev/null; then
        SOURCE_CLAUDE="${TEMP_DIR}/repo/.claude"
    else
        echo "错误: 无法下载配置，请检查网络连接！"
        exit 1
    fi
fi

if [ ! -d "${SOURCE_CLAUDE}" ]; then
    echo "错误: 未能获取到有效的 .claude 配置目录！"
    exit 1
fi

# 1. 确保目标目录存在
mkdir -p "${TARGET_CLAUDE}"

# 2. 赋予状态栏脚本执行权限
chmod +x "${SOURCE_CLAUDE}/statusline-command.sh" 2>/dev/null || true

echo "正在同步配置文件到 ${TARGET_CLAUDE} ..."

# 3. 复制核心配置文件
cp -a "${SOURCE_CLAUDE}/CLAUDE.md" "${TARGET_CLAUDE}/"
cp -a "${SOURCE_CLAUDE}/statusline-command.sh" "${TARGET_CLAUDE}/"
[ -f "${SOURCE_CLAUDE}/config.json" ] && cp -a "${SOURCE_CLAUDE}/config.json" "${TARGET_CLAUDE}/"
[ -f "${SOURCE_CLAUDE}/.mcp.json" ] && cp -a "${SOURCE_CLAUDE}/.mcp.json" "${TARGET_CLAUDE}/"
[ -f "${SOURCE_CLAUDE}/settings.json" ] && cp -a "${SOURCE_CLAUDE}/settings.json" "${TARGET_CLAUDE}/"

# 4. 复制 rules 规则库
if [ -d "${SOURCE_CLAUDE}/rules" ]; then
    mkdir -p "${TARGET_CLAUDE}/rules"
    cp -a "${SOURCE_CLAUDE}/rules/"* "${TARGET_CLAUDE}/rules/"
fi

# 5. 配置 ANTHROPIC_AUTH_TOKEN 检查
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
            sed -i "s/YOUR_ANTHROPIC_AUTH_TOKEN/${CURRENT_TOKEN}/g" "${TARGET_CLAUDE}/settings.json"
            echo "已自动使用环境变量中的 Token 替换配置中的占位符！"
        else
            echo "提示: 当前 settings.json 中的 ANTHROPIC_AUTH_TOKEN 为占位符。"
            echo "后续可手动编辑 ~/.claude/settings.json 或直接设置环境变量 export ANTHROPIC_AUTH_TOKEN=..."
        fi
    else
        echo "settings.json 中的 Token 已就绪。"
    fi
fi

echo ""
echo "=========================================="
echo "配置恢复完成！"
echo "目标路径: ${TARGET_CLAUDE}"
echo "包含: 状态栏脚本 (statusline), 规则 (rules), settings.json 配置等"
echo "=========================================="
