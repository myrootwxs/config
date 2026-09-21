#!/usr/bin/env bash
# Claude Code 配置一键安装与恢复脚本（支持本地执行与 curl | bash 管道执行）
set -e

echo "=========================================="
echo "      Claude Code 配置一键安装工具         "
echo "=========================================="

REPO_SLUG="myrootwxs/config"
TARGET_CLAUDE="${HOME}/.claude"
TARGET_AGENTS="${HOME}/.agents"
TEMP_DIR=""

# 退出时自动清理临时目录
cleanup() {
    if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

# 检查当前目录下是否存在 .claude
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
    echo "未在本地检测到 .claude 目录，正在从 GitHub (${REPO_SLUG}) 拉取最新配置..."
    TEMP_DIR="$(mktemp -d)"

    CLONED=0
    # 策略 1: 优先尝试 SSH 克隆
    if git clone --depth=1 "git@github.com:${REPO_SLUG}.git" "${TEMP_DIR}/repo" 2>/dev/null; then
        SOURCE_CLAUDE="${TEMP_DIR}/repo/.claude"
        CLONED=1
    # 策略 2: 尝试 GitHub CLI
    elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        echo "使用 gh CLI 拉取仓库..."
        gh repo clone "${REPO_SLUG}" "${TEMP_DIR}/repo" -- --depth=1 2>/dev/null && {
            SOURCE_CLAUDE="${TEMP_DIR}/repo/.claude"
            CLONED=1
        }
    # 策略 3: 使用 GITHUB_TOKEN 或 GH_TOKEN 环境变量拉取归档
    elif [ -n "${GITHUB_TOKEN:-$GH_TOKEN}" ]; then
        TOKEN="${GITHUB_TOKEN:-$GH_TOKEN}"
        echo "使用 Token 通过 GitHub API 拉取归档..."
        curl -fsSL -H "Authorization: token ${TOKEN}" \
            "https://api.github.com/repos/${REPO_SLUG}/tarball/main" | tar -xz -C "${TEMP_DIR}" --strip-components=1 2>/dev/null && {
            SOURCE_CLAUDE="${TEMP_DIR}/.claude"
            CLONED=1
        }
    fi

    # 策略 4: 如果前面都失败，回退到 HTTPS 克隆（若需要会提示输入账号密码/Token）
    if [ "$CLONED" -ne 1 ]; then
        echo "正在通过 HTTPS 克隆（若提示请输入 GitHub 账号与 Token）..."
        git clone --depth=1 "https://github.com/${REPO_SLUG}.git" "${TEMP_DIR}/repo"
        SOURCE_CLAUDE="${TEMP_DIR}/repo/.claude"
    fi
fi

if [ ! -d "${SOURCE_CLAUDE}" ]; then
    echo "错误: 未能获取到 .claude 配置目录！"
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
    # 建立软链接 ~/.claude/skills -> ~/.agents/skills
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
