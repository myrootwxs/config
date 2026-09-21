# Claude Code 配置与快速恢复指南 (README_zh.md)

本仓库用于统一备份、版本管理和在新环境下快速恢复 Claude Code 运行配置。

---

## 目录结构

```text
.
├── .claude/                    # Claude 核心配置目录
│   ├── CLAUDE.md               # 全局用户指南与编码规范
│   ├── statusline-command.sh   # 终端状态栏显示脚本（模型、思考强度、上下文量/占比、输出速率）
│   ├── settings.json           # 默认全局配置（权限控制、环境配置、状态栏绑定等）
│   ├── settings_*.json         # 各模型场景配置预设 (deepseek, cpa, minimax, opg 等)
│   ├── rules/                  # 全局规则库 (如 context7.md 等)
│   ├── skills/                 # 通用技能集合 (context7-mcp, find-skills, git-commit, grill-me, i-have-adhd)
│   ├── config.json             # 基础配置项
│   └── .mcp.json               # MCP 服务器配置
├── install.sh                  # 一键安装恢复脚本（支持 curl 管道执行与本地执行）
├── .gitignore                  # 自动排除历史会话、日志、缓存、Hooks、Plugins 与临时数据
├── README.md                   # 英文/通用说明文档
└── README_zh.md                # 中文完整指南与使用手册
```

---

## 在新环境快速恢复

### 方式 1：通过 curl 管道直接执行（推荐）

由于本仓库为私有仓库（Private Repo），在目标设备上执行时需携带访问凭据。根据目标机器的环境，任选一条执行即可：

#### A. 带有 GitHub Token 时（最通用、无交互）
若机器已配置了 `GITHUB_TOKEN` 环境变量，或手动填入 Token：
```bash
curl -fsSL -H "Authorization: token ${GITHUB_TOKEN:-YOUR_GITHUB_TOKEN}" \
  https://raw.githubusercontent.com/myrootwxs/config/main/install.sh | bash
```

#### B. 安装并登录了 `gh` CLI
```bash
gh api repos/myrootwxs/config/contents/install.sh -H "Accept: application/vnd.github.raw" | bash
```

> **执行原理说明**：`install.sh` 内置管道检测与临时工作区机制。通过管道执行时，会自动按 `SSH` → `gh CLI` → `API Tarball` → `HTTPS` 的优先级拉取配置、恢复目录与权限，并在安装完成后自动清理临时文件。

---

### 方式 2：克隆仓库后执行

在已配置 SSH 密钥的机器上：

```bash
cd ~
git clone git@github.com:myrootwxs/config.git
cd config
./install.sh
```

---

### 方式 3：手动直接提取

由于仓库内已组织好 `.claude/` 目录，克隆后也可直接拷贝对齐路径：

```bash
# 1. 拷贝核心配置到 ~/.claude/
cp -a ~/config/.claude ~/.claude/

# 2. 赋予状态栏脚本执行权限
chmod +x ~/.claude/statusline-command.sh

# 3. 恢复 skills 软链接
mkdir -p ~/.agents
cp -a ~/.claude/skills ~/.agents/
ln -sf ~/.agents/skills ~/.claude/skills
```

---

## Token 与密钥配置说明

为了保证账号安全，仓库已对各 `settings*.json` 中的 `ANTHROPIC_AUTH_TOKEN` 进行了脱敏处理（值为占位符 `YOUR_ANTHROPIC_AUTH_TOKEN`）。

在新设备恢复后，请任选一种方式填入您的真实 Token：

### 方式一（推荐）：配置环境变量
在 shell 启动脚本（如 `~/.bashrc`、`~/.zshrc` 或 `~/.config/fish/config.fish`）中添加：
```bash
export ANTHROPIC_AUTH_TOKEN="your_actual_anthropic_token"
```
（`install.sh` 脚本在执行时若检测到该环境变量，会自动替换配置中的占位符）

### 方式二：直接编辑 settings.json
直接修改 `~/.claude/settings.json`（或对应的 `settings_*.json`），将 `YOUR_ANTHROPIC_AUTH_TOKEN` 替换为真实 Token。

---

## 状态栏显示效果说明

配置中包含的状态栏脚本（`statusline-command.sh`）展示效果如下：

```text
deepseek-flash[1m] │ effort:xhigh │ ctx 186.0k/400.0k │ 47% │ 82.3 tok/s
```

- **当前模型**：显示运行模型名称
- **思考强度**：显示思考级别（如 `effort:xhigh`、`effort:medium`），不支持时回退显示思考开关状态
- **上下文使用量**：格式化展示当前已用量与窗口总上限（如 `186.0k/400.0k`）
- **窗口占比**：百分比显示并按阈值变色（<50% 绿色、50%~79% 黄色、≥80% 红色）
- **模型输出速率**：由会话记录推算近期输出速度（`tok/s`）
