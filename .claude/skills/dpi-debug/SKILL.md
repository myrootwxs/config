---
name: dpi-debug
description: "指导 DPI 程序的模块级调试与验证：核对运行配置、构建、按需安装头文件、部署运行库、等待服务就绪、发送测试报文并检查日志和 XDR 输出。用户要求调试、验证、测试 DPI、部署验证、配置排查，或排查模块修改在 yahong51 开发环境的运行结果时使用。"
---

# DPI 调试与验证

在 `/home/wxs/dpi20_ice` 对已修改模块完成一次可追溯的运行验证。遵循仓库 `AGENTS.md` 和目标模块的局部说明；不进行根工程全量构建，不改动无关文件。

## 执行前检查

- 确认目标模块、预期行为和对应输出类型；先阅读该模块的 `AGENTS.md`、`CLAUDE.md` 和现有实现。
- 先查看 `git status --short`，保留与当前任务无关的已有改动。
- 将安装至 `/opt/dpi`、复制运行库和重启进程视为影响运行环境的操作：执行前说明影响；除非用户已授权，不自行重启 DPI。
- 若修改了对外公共头文件或 `.tab` 定义，构建后执行模块 `make install`，让下游模块使用更新后的头文件。

## 配置文件定位与核验

### 配置层级

DPI 运行时以 `/opt/dpi` 为配置根目录。不要将仓库中的模板、规则源文件与正在生效的配置混为一谈；排查运行问题时先检查运行时文件，再回溯仓库来源。

| 层级 | 运行时位置 | 仓库来源或工具 | 用途 |
| --- | --- | --- | --- |
| 启动与硬件 | `/opt/dpi/syscfg.json` | 由 `cpucfg` 或 `ghcfg/xsajson/xsajson.sh` 生成 | CPU、NUMA、网卡和模块配置文件选择；`xsa` 启动时首先加载。 |
| 主模块参数 | `/opt/dpi/xsaconf/xsa.json`（以及按需的 `cpuxsa.json`） | 工互场景模板：`main/tool/mconf/config_manager/ghcfg/xsajson/xsa.json` | 各模块的 JSON 参数；模块通过各自 `*ConfLoadJson()` 读取，`flow` 额外使用 `cpuxsa.json`。 |
| 模块开关 | `/opt/dpi/<mod.cfg>`（通常为 `mod.cfg` 或场景指定文件） | `main/xsa/mod.cfg`、`main/xsa/cfg/*.cfg` | 控制模块是否装载；`0` 为关闭、`1` 为开启、`2` 为强制保留。 |
| 通用与会话参数 | `/opt/dpi/xsaconf/common.ini`、`/opt/dpi/xsaconf/sessionKey.ini` | `main/xsa/xsaconf/common.ini`；会话密钥由工互接收服务落盘 | 上传模块会监控文件变更并重载；`sessionKey.ini` 是工互 SM4 独立通道。 |
| 规则与话单模板 | `/opt/dpi/{xsaconf,xdrconf,rsconf,dsconf,euconf,malconf,fsnortconf,cpsconf,uploadfileconf}/rule/` | `main/xsa/<配置目录>/rule/` | 协议识别、上传、恶意检测、XDR/RS/DS 模板等业务规则。 |
| 工互接收服务 | `/opt/dpi/InduNetSecRxConf/settings.jsonc` | `main/InduNetSecRx/InduNetSecRxConf/settings.jsonc` | `security.token`、注册与监听地址、SM2 密钥路径等；`foxdr` 同时读取其中的 `security.token` 并共享给 `malscan`、`xdrtxtlog`。 |
| 场景标识 | `/opt/dpi/config/rule/dpiconfig.ok` | `main/tool/mconf/cfgset.sh` 或 `ghcfg` | 保存当前配置模型标识，供上传等模块判断场景。 |

`main/xsa` 的 `xsaconf/xsa.json` 可能不随源码树保存；不要因仓库缺失该文件而认定运行配置不存在。应检查 `/opt/dpi/xsaconf/xsa.json`，或查阅 `ghcfg/xsajson/xsa.json` 的场景模板。

### 先读后改

调试前按影响范围选择核验项，避免打印令牌、密码和私钥内容：

```bash
for f in \
    /opt/dpi/syscfg.json \
    /opt/dpi/xsaconf/xsa.json \
    /opt/dpi/xsaconf/common.ini \
    /opt/dpi/config/rule/dpiconfig.ok; do
    test -e "$f" && stat -c '%y %n' "$f" || printf '缺失: %s\\n' "$f"
done

modfile=$(sed -n 's/.*"modfile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /opt/dpi/syscfg.json | head -1)
test -n "$modfile" && test -f "/opt/dpi/$modfile" && \
    grep -E '^(<module>|foxdr|xdrtxtlog|uploadfile):' "/opt/dpi/$modfile"
```

- 将 `<module>` 替换为本次目标模块；模块清单由 `syscfg.json` 的 `modfile` 决定（当前工互环境通常为 `indust.cfg`），不要硬编码为 `mod.cfg`。
- 规则问题先核对对应的 `/opt/dpi/<conf>/rule/<rule>` 是否存在、更新时间和权限，再检查模块日志中的加载失败信息。
- `settings.jsonc` 是 JSONC，不可直接假设标准 JSON 工具能解析；只确认文件存在、权限和非敏感字段，严禁在终端或交付内容中输出 `security.token`、私钥或会话密钥。
- 未经用户明确授权，不修改 `/opt/dpi` 下运行配置，不执行场景切换，也不重启 DPI。

### 工互场景切换

工互探针/网安场景入口为 `/opt/dpi/mconf/ghcfg/gh_mod_switch.sh`，源码位于 `main/tool/mconf/config_manager/ghcfg/`。该脚本支持 `ic`、`icns`，会备份并改写 `syscfg.json`、`xsaconf/xsa.json`、`dpi_monitor.cfg`、`dpiconfig.ok` 和多类规则文件，且会停止、随后重启 `dpimonitor`。

仅当用户明确要求切换场景且已确认运行环境影响时，才可执行：

```bash
cd /opt/dpi/mconf/ghcfg
./gh_mod_switch.sh ic   # 或 icns
```

若只需验证代码改动，禁止以场景切换替代最小化配置核验。

## 调试流程

### 1. 构建模块

```bash
cd /home/wxs/dpi20_ice/<module_dir>
/root/make.sh
```

模块没有 `sh/automake.sh` 时，改用其 README 或相邻构建脚本规定的入口。构建失败时先报告首个编译错误及受影响文件，不以旧 `.so` 继续验证。

### 2. 按需安装公共头文件

```bash
make -C /home/wxs/dpi20_ice/<module_dir> install
```

仅在公共头文件、`*.tab` 生成的 `*_tab.h` 或跨模块接口变更时执行。`/root/make.sh` 只负责编译，不安装头文件。

### 3. 部署并重启

确认构建产物名称后再复制，避免用占位符或旧库覆盖运行环境：

```bash
cp /home/wxs/dpi20_ice/lib/platform/<lib>.so.1.0.0 /opt/dpi/lib/platform/
```

由用户或既定运行维护流程重启 DPI。不要把重启操作和构建命令混为一条不可检查的命令。

部署前如本次验证依赖配置，记录实际检查过的配置路径、修改时间和相关模块开关；不要复制仓库模板直接覆盖 `/opt/dpi` 中现有配置。

### 4. 等待服务就绪

```bash
timeout 120 sh -c 'tail -n 0 -F /var/log/dpi.log | grep --line-buffered -m1 "start run loop"'
```

日志出现 `start run loop` 后再发包；超时则检查 `/var/log/dpi.log` 中的启动和加载错误，勿假定服务已可收包。

### 5. 发包与验证

```bash
cd /root/send && ./send.py NS
sleep 3
today=$(date +%Y%m%d)
for d in cyberAttacks connLog payloadRusult fileMonitorResult flowFile maliceFile; do
    printf '=== %s ===\\n' "$d"
    ls -lt "/xdr/$d/$today/" 2>/dev/null | head -3
done
```

仅检查与本次改动对应的目录、文件名、内容字段和日志。确认某个 `.bin` 文件的封装特征可使用：

```bash
head -c 200 /path/to/file.bin | xxd | head -8
```

`50 4b 03 04` 表示 ZIP 容器头，`31 2e 30 7c` 对应可读的 `1.0|` 文本开头；结合上传规则和业务预期判断是否正确，不能仅凭 ZIP 头断定加密状态。

## 常用路径

- DPI 主进程：`/opt/dpi/xsa`
- 运行库目录：`/opt/dpi/lib/platform/`
- 主日志：`/var/log/dpi.log`
- 上传规则：`/opt/dpi/xsaconf/rule/upload.rule`
- 主配置：`/opt/dpi/syscfg.json`、`/opt/dpi/xsaconf/xsa.json`（按需检查 `cpuxsa.json`）
- 模块开关：`/opt/dpi/<modfile>`（文件名由 `syscfg.json` 决定，工互常为 `indust.cfg`）
- 工互配置：`/opt/dpi/InduNetSecRxConf/settings.jsonc`
- 工互场景工具：`/opt/dpi/mconf/ghcfg/gh_mod_switch.sh`
- 上传源目录：`/dev/shm/sess/`
- XDR 输出目录：`/xdr/`
- 测试发包目录：`/root/send/`

## 交付结果

报告模块构建结果、是否安装头文件/部署运行库、DPI 就绪证据、所用报文、相关输出路径与关键验证结果。失败时提供命令、首个错误或关键日志以及下一步诊断建议。
