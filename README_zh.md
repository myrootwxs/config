# Claude Code 配置与快速恢复指南 (README_zh.md)

本仓库用于统一备份、版本管理和在新环境下快速恢复 Claude Code 运行配置。

---

## ⚡ 一键极速恢复（免 Token）

由于本仓库为公开仓库，在**任意新机器/环境**的终端中，无需 GitHub 账号、无需 Token，直接运行以下单行命令即可完成一键安装：

```bash
curl -fsSL https://raw.githubusercontent.com/myrootwxs/config/main/install.sh | bash
```

> **自动处理内容**：
> - 自动从 GitHub 下载最新配置并解压部署到 `~/.claude/`；
> - 自动为状态栏脚本赋予可执行权限；
> - 自动检测当前环境变量中的 `$ANTHROPIC_AUTH_TOKEN` 并写入配置；
> - 自动清理临时下载缓存，无残留。

---

## 目录结构

```text
.
├── .claude/                    # Claude 核心配置目录
│   ├── CLAUDE.md               # 全局用户指南与通用编码规范
│   ├── statusline-command.sh   # 终端状态栏显示脚本（模型、思考强度、上下文量/占比、输出速率）
│   ├── settings.json           # 核心全局配置（权限白名单、环境变量映射、状态栏绑定等）
│   ├── rules/                  # 全局规则库 (如 context7.md)
│   ├── config.json             # 基础配置项
│   └── .mcp.json               # MCP 服务器配置
├── install.sh                  # 一键极速安装恢复脚本（支持 curl 管道直接执行）
├── .gitignore                  # 自动排除历史会话、日志、缓存、Hooks、Plugins 与临时数据
├── README.md                   # 英文/通用说明
└── README_zh.md                # 中文完整指南
```

---

## 其他恢复方式

### 方式 2：克隆仓库后执行

```bash
cd ~
git clone https://github.com/myrootwxs/config.git
cd config
./install.sh
```

---

### 方式 3：手动直接提取

由于仓库内已组织好 `.claude/` 目录结构，克隆后可直接拷贝至用户根目录：

```bash
# 拷贝核心配置到 ~/.claude/
cp -a ~/config/.claude ~/.claude/

# 赋予状态栏脚本执行权限
chmod +x ~/.claude/statusline-command.sh
```

---

## Token 与密钥配置说明

为了保证账号安全，仓库中 `settings.json` 的 `ANTHROPIC_AUTH_TOKEN` 已脱敏（占位符为 `YOUR_ANTHROPIC_AUTH_TOKEN`）。

恢复配置后，可通过以下两种方式之一使 Token 生效：

### 方式一（推荐）：配置环境变量
在终端配置文件（如 `~/.bashrc`、`~/.zshrc` 或 `~/.config/fish/config.fish`）中添加：
```bash
export ANTHROPIC_AUTH_TOKEN="your_actual_anthropic_token"
```
（`install.sh` 脚本在执行时若检测到该环境变量，会自动替换配置中的占位符）

### 方式二：直接编辑 settings.json
修改 `~/.claude/settings.json`，将 `YOUR_ANTHROPIC_AUTH_TOKEN` 替换为真实 Token 即可。

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
