# Claude Code 配置仓库 (config)

本仓库用于同步和备份 Claude Code 运行环境配置，可在新机器/环境中一键恢复。

## 目录结构

```text
.
├── .claude/                    # Claude 核心配置目录
│   ├── CLAUDE.md               # 全局用户指南与编码规范
│   ├── statusline-command.sh   # 终端状态栏显示脚本（模型、思考强度、上下文、速率等）
│   ├── settings.json           # 默认全局配置（权限、环境变量、状态栏绑定等）
│   ├── settings_*.json         # 各模型场景配置预设 (deepseek, cpa, minimax, opg 等)
│   ├── rules/                  # 全局规则库 (如 context7.md 等)
│   ├── skills/                 # 常用通用技能集合 (context7-mcp, find-skills, git-commit 等)
│   ├── config.json             # 基础配置项
│   └── .mcp.json               # MCP 服务器配置
├── install.sh                  # 一键恢复脚本
├── .gitignore                  # 自动排除历史会话、日志、缓存、Hooks、Plugins 与临时数据
└── README.md
```

## 在新环境快速恢复

### 方式 1：一键脚本恢复（推荐）

在新设备终端中执行：

```bash
cd ~
git clone git@github.com:myrootwxs/config.git
cd config
./install.sh
```

脚本会自动：
- 将 `.claude` 中的配置文件同步到 `~/.claude/`
- 同步通用 `skills` 到 `~/.agents/skills` 并建立软链接
- 自动赋予状态栏脚本执行权限
- 检查并自动替换 `ANTHROPIC_AUTH_TOKEN`（如环境变量已配置）

### 方式 2：直接提取使用

由于仓库内已组织好 `.claude/` 目录，克隆后也可以直接将目录同步到用户主目录：

```bash
# 拷贝到 ~/.claude/
cp -a ~/config/.claude ~/.claude/

# 恢复 skills 软链接
mkdir -p ~/.agents
cp -a ~/.claude/skills ~/.agents/
ln -sf ~/.agents/skills ~/.claude/skills
```

## Token 配置说明

为了保证安全，仓库已对各 `settings*.json` 中的 `ANTHROPIC_AUTH_TOKEN` 进行了脱敏处理（值为 `YOUR_ANTHROPIC_AUTH_TOKEN`）。

在新设备恢复后，请任选一种方式填入您的真实 Token：

1. **方式一（推荐）：配置环境变量**
   ```bash
   export ANTHROPIC_AUTH_TOKEN="your_actual_token_here"
   ```
   （可写入 `~/.bashrc`、`~/.zshrc` 或 `~/.config/fish/config.fish` 中）

2. **方式二：直接修改 settings 文件**
   编辑 `~/.claude/settings.json`，将 `YOUR_ANTHROPIC_AUTH_TOKEN` 替换为真实 Token。
