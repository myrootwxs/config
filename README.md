# Claude Code Configuration Repository (config)

This repository provides centralized management, synchronization, and one-command recovery for your Claude Code environment.

---

## ⚡ Quick One-Line Install (No Token Required)

Since this repository is public, you can restore your complete Claude Code configuration on **any new machine** with a single command without needing GitHub tokens or SSH keys:

```bash
curl -fsSL https://raw.githubusercontent.com/myrootwxs/config/main/install.sh | bash
```

> **Automated Setup**:
> - Downloads and installs the configuration to `~/.claude/`;
> - Sets executable permissions for the status line script;
> - Automatically detects `$ANTHROPIC_AUTH_TOKEN` from the environment if available;
> - Cleans up temporary installation archives automatically.

---

## Directory Structure

```text
.
├── .claude/                    # Core Claude Code configuration directory
│   ├── CLAUDE.md               # Global instructions and guidelines
│   ├── statusline-command.sh   # Terminal status line script (model, effort, context, tok/s)
│   ├── settings.json           # Global settings (permissions, env, statusLine hook)
│   ├── rules/                  # Rule definitions (e.g. context7.md)
│   ├── config.json             # Basic configuration
│   └── .mcp.json               # MCP server configuration
├── install.sh                  # One-command installer (supports curl pipe and local execution)
├── .gitignore                  # Excludes sessions, logs, cache, and runtime data
├── README.md                   # English documentation
└── README_zh.md                # Detailed Chinese guide
```

---

## Alternative Install Methods

### Clone and Run

```bash
cd ~
git clone https://github.com/myrootwxs/config.git
cd config
./install.sh
```

---

## Token Configuration

For security reasons, `ANTHROPIC_AUTH_TOKEN` in `settings.json` is set to the placeholder `YOUR_ANTHROPIC_AUTH_TOKEN`.

After installing, provide your token in either way:

1. **Option 1 (Recommended): Environment Variable**
   ```bash
   export ANTHROPIC_AUTH_TOKEN="your_actual_anthropic_token"
   ```
   (Add to `~/.bashrc`, `~/.zshrc`, or `~/.config/fish/config.fish`)

2. **Option 2: Edit settings.json directly**
   Replace `YOUR_ANTHROPIC_AUTH_TOKEN` in `~/.claude/settings.json`.
