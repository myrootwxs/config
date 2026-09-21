---
name: dpi-e2e-test
description: "在 yahong51 上跑 DPI 端到端上报测试：三场景通用（ic/icns/clw）。先核对 /opt/dpi/config/rule/dpiconfig.ok 选中当前场景，再调用 /root/indust_test/{ic,ns,clw}/test_indust_xdr.sh 完成停机→清环境→发包→话单校验全流程，并按各场景预期输出集合解读 check_xdr_full.py（ic/icns）/ check_clw_xdr.py（clw）校验报告、排查上报问题。用户要求测试 DPI/工互/icns/车联网/clw 上报、跑 test_indust_xdr.sh、跑 indust_test、校验话单/XDR、排查上报输出时使用。"
---

# DPI 端到端测试（ic / icns / clw）

在 yahong51 开发服务器上，用 `/root/indust_test/` 下的脚本对 DPI 完成一次端到端上报测试：发测试报文 → 落话单到 `/xdr/` → 自动校验字段。本 skill 只做测试与结果解读，不修改业务代码，不擅自切换场景或改运行配置。

`/root/indust_test/` 下有**三套**场景测试，结构同构（停机→清环境→发包→校验）但预期输出与校验器差异很大。**先看 `dpiconfig.ok` 选中场景，再决定走哪条子流程**。

## 适用与边界

- 依赖 yahong51 环境：测试脚本在 `/root/indust_test/{ic,ns,clw}/`，DPI 在 `/opt/dpi`（软链），话单落 `/xdr/`，发包在 `/root/send/`。
- 三套 `test_indust_xdr.sh` 内部都会**停止并重启 DPI**（`dpikill.sh`→`dpirun.sh`），属影响运行环境的操作；执行前向用户确认，不要与其它调试或构建任务并发。
- 场景切换（切到 ic/icns）、改 `/opt/dpi` 配置须用户明确授权；本 skill 仅核验当前场景，不自行切换。
- clw 场景**不部署** DPI：用现成的 `/opt/dpi_release`（真实目录），脚本只切软链；不要 `rm -rf /opt/dpi_release`。
- 退出码统一约定：`0` = PASS（可有 WARN），`1` = FAIL（存在 CRC 错或 ERROR）。

## 三场景速查表（核心入口）

| 维度 | ic（工互探针） | icns（工互网安） | clw（车联网） |
| --- | --- | --- | --- |
| 脚本入口 | `ic/test_indust_xdr.sh` | `ns/test_indust_xdr.sh` | `clw/test_indust_xdr.sh` |
| 校验脚本 | `ic/check_xdr_full.py` | `ns/check_xdr_full.py`（+ `decode_sftp.py` 同目录必留） | `clw/check_clw_xdr.py` + `clw/check_clw_values.py`（+ `check_coverage.py` 调试用） |
| 场景目录 | `/opt/dpi_ic`（软链） | `/opt/dpi_icns`（软链） | `/opt/dpi_release`（**真实目录**） |
| `dpiconfig.ok` | `indust_ic` | `indust_icns` | `com_cmcc_isbnsnsds` |
| 默认发包 | `NS` | `NS` | `clwpcap`（实际 pcap 在 `clwpcap/clwpcap/` 子目录） |
| XDR 根 | `/xdr/upload/` | `/xdr/upload/` | `/xdr/`（`check_clw_values.py` 写死 `/xdr/indust2`） |
| 话单格式 | 明文 `.txt`/`.tar.gz`/`.zip`/`.zip_complete` | SM4+zip 密文 `.bin`/`.zip` | 明文 `.txt` |
| 启动就绪标志 | `start run loop` | `start run loop` | `start run loop` |
| 启动超时 `WAIT_START_TIMEOUT` | 3600s | 3600s | 180s |
| 等待话单 | 180s 一次性 | 60s 一次性 | 轮询 180s，首个出现后 `SETTLE=20s` |
| 是否自动部署 DPI | 是（FTP 取包 install） | 是（+ 引擎部署 `ghnsstd` + `liboutput.so`） | **否**（用现成 `/opt/dpi_release`） |
| 是否切 `gh_mod_switch` | 是（`ic`） | 是（`icns`） | **否** |
| 输出控制 | 默认关键节点 | 默认关键节点 + `DETAIL_LOG=/tmp/indust_xdr_test_detail.log`；`TEST_VERBOSE=1` 展开 | 默认关键节点 |

**首选入口**：先看 `dpiconfig.ok` → 选行 → 走对应子流程。

## 公共前置核验

### 1. 确认当前场景

```bash
cat /opt/dpi/config/rule/dpiconfig.ok    # 三选一: indust_ic / indust_icns / com_cmcc_isbnsnsds
ls -l /opt/dpi                            # 应是软链;clw 指向 /opt/dpi_release
```

不是预期场景（如 `indust_ic` 但脚本跑的是 `ns/test_indust_xdr.sh`）→ 应**先提示用户切换**，不要自行执行 `gh_mod_switch.sh`。切换入口（需用户授权）：

```bash
cd /opt/dpi/mconf/ghcfg && ./gh_mod_switch.sh ic   # 或 icns（clw 不切）
```

### 2. 确认脚本与发包目录就位

```bash
ls -l /root/indust_test/{ic,ns,clw}/test_indust_xdr.sh
ls -l /root/indust_test/{ic,ns}/check_xdr_full.py /root/indust_test/ns/decode_sftp.py
ls -l /root/indust_test/clw/check_clw_xdr.py /root/indust_test/clw/check_clw_values.py
ls -d /root/send/NS /root/send/clwpcap    # 默认发包集
```

### 3. 关键运行配置存在性（只读核验，不打印内容）

| 路径 | 适用场景 | 作用 |
| --- | --- | --- |
| `/opt/dpi/xsaconf/sessionKey.ini` | icns（必需）、ic（无） | icns 话单 SM4 解密密钥；缺失时从 `ns/conf/` 兜底 |
| `/opt/dpi/syscfg.json` | ic/icns | `modfile` 字段决定加载的 cfg（工互通常 `indust.cfg`） |
| `/opt/dpi/InduNetSecRxConf/settings.jsonc` | icns | `security.token`；严禁输出 token/私钥内容 |
| `/opt/dpi/fsnortconf/rule/ns_event.txt` | icns | 事件分类映射（icns 用附录表 9 版本覆盖过） |
| `/opt/dpi/InduNetSecRxConf/rule_store.db` | icns | InduNetSecRx self-heal 每 60s 用它投影覆盖规则文件 |

## 一键执行（按场景分支）

```bash
# ic（工互探针）
cd /root/indust_test/ic && ./test_indust_xdr.sh [发包目录...]

# icns（工互网安）
cd /root/indust_test/ns && ./test_indust_xdr.sh [发包目录...]

# clw（车联网）
cd /root/indust_test/clw && ./test_indust_xdr.sh [发包目录...]

# 双场景串联（ic + icns，不含 clw；crontab 风格）
/root/indust_test/test_all.sh [发包目录...]
```

`test_indust_xdr.sh` 内部 7 步（无需手工干预）：

1. **场景软链 + 配置一致性**（`scene.sh:ensure_scene_config`；clw 仅切软链不验 `ghcfg`）
2. **停止 DPI**（`./dpikill.sh`，30s 轮询 `pgrep -x xsa`）
3. **清空 `/var/log/dpi.log`** + `pkill -HUP rsyslogd`（rsyslog 持旧句柄会让新日志写不进去；**三场景都需要**）
4. **清空 `/xdr/*`**（icns 还清引擎 `/appslog/dsms/processResult/{indust_ns,data_recog}`）
5. **启动 DPI** + 轮询 `/var/log/dpi.log` 出现 `start run loop`（超时按场景表），命中后再 `sleep EXTRA_WAIT=10s`
6. **发包**：`cd /root/send && ./send.py <发包目录>`（默认网卡 `ens11f0`；不匹配在 `send.py` 用 `-i` 改）
7. **等待话单** + **字段校验**（调对应 check 脚本，退出码 0=PASS）

关键变量（在脚本顶部，排查时可按需调大）：

- `START_MARK` = `start run loop`
- `WAIT_START_TIMEOUT`（按场景表）
- `EXTRA_WAIT` = 10
- `WAIT_OUTPUT`（ic=180, ns=60, clw=180 轮询 + `SETTLE=20`）
- ns 额外：`RULE_SET=test|full`、`TEST_VERBOSE=0|1`、`FTP_PASSWORD`（优先 env，否则 `~/.netrc`）
- clw 额外：`WAIT_OUTPUT`、`SETTLE`、`POLL_INTERVAL=3`

## 各场景预期输出集合（核心）

### ic（工互探针，明文，按 `upload.rule` 分目录）

| 目录 | name_type | ic 预期 | 说明 |
| --- | --- | --- | --- |
| `indust` | 通联日志（22 字段，分隔符 `\|`） | **有** | 基础协议识别 |
| `netthreat` | 网安网络威胁日志（45 字段，分隔符 `\|`） | **有** | 来源 `.tar.gz` |
| `xrt_stat_output` / `filter` / `dataidentity` / `datarisk` / `datathreat` / `api_file` | — | **仅统计文件数**，不做字段校验 | `STAT_ONLY_DIRS` |

判定要点：

- **0 条不一定是失败**：要先看 `upload.rule` 中该类型上报行是否被注释（详见 ic 特有坑）。
- `indust` 协议名只做非空校验（`APP_PROTO_NAMES` 实测样本超出集合，故放弃枚举）。
- `netthreat` 的 `logId` 有 A/B 两种格式并存（详见 ic 特有坑）。

### icns（工互网安，SM4+zip 密文，按 `name_type` 清空部分规则）

| 目录 | name_type | icns 预期 | 说明 |
| --- | --- | --- | --- |
| `cyberAttacks` | 23 网络威胁日志（59 字段，分隔符 `\|`） | **有** | `eu_snort.rules`(SID≤10亿内置)、`inner_evilpkt_ioc.rule` 保留 |
| `connLog` | 会话日志（25 字段，分隔符 `\|\|\|`；check 内 `EXPECT_LEN=25`、注释 24） | **有** | 基础会话还原 |
| `flowFile` | 流量文件 | **有** | 仅做 CRC，不做字段校验 |
| `payloadRusult` | 25 恶意报文日志（30 字段，分隔符 `\|`） | **无（0 条正常）** | `g_snort.rule` / `evilpkt_ioc.rule` 等被清空 |
| `fileMonitorResult` | 24 恶意文件日志（26 字段，分隔符 `\|`） | **无（目录可能不存在）** | malscan / YARA / MD5 黑名单等被清空 |
| `dataRecognitionResult` | v5.3 引擎新增（14 字段，dataInfo 按 `dataType\|dataLevel\|dataContent` × N 循环） | **可选** | 行内 `\|` 冲突，必须走 `parse_data_recog_line`；段数 ≠ `13 + 3*N` 即 `__结构__` ERROR |

判定要点：

- `payloadRusult`、`fileMonitorResult` 在 icns 下**0 条是正常**，不算测试失败。
- 若 icns 下出现 `payloadRusult`/`fileMonitorResult` 新输出，说明场景未真正切到 icns 或清空规则未生效，回查 `g_snort.rule`、`evilpkt_ioc.rule`、`malscan.rule` 等。
- 引擎 INDUST_NS 本地明文 `/appslog/dsms/processResult/indust_ns` 通常 0 文件（被 `uploadfile` 守护即时搬走），不要看到 0 就报错。
- `test_indust_xdr.sh` 只要求 `/xdr` 下有任意 `.bin/.zip` 即过"有输出"关；最终成败以第 7 步 `check_xdr_full.py` 退出码为准。
- 第二参数启用指令一致性校验：`python3 ns/check_xdr_full.py /xdr/upload ns/data/command_baselines.json`（`cyberAttacks`/`connLog` 不参与；只对 `payloadRusult`/`fileMonitorResult` 启用跨名映射 `eventLevel←severity`、`isPCAP←isUploadFile`）。

### clw（车联网，明文 `/xdr/indust2/`，按协议分目录）

| 协议 | PROTO_MARK | 校验模式 |
| --- | --- | --- |
| `GBT32960` | `GBT32960` | 表头 + 关键字段 +（单目录）值级 |
| `JT808` | `JT808` | 同上 |
| `JT808_2019` | `JT808_2019` | 同上 |
| `JT809` | `JT809` | 同上 |
| `JT905` | `JT905_4`（**fo 按 harddecode 表实际输出为 `JT905_4`**） | 同上 |
| `JT905_2` | `JT905_2` | 同上 |

校验模式从 `/opt/dpi/xsaconf/xsa.json` 读 `indust.clw_output_mode`：

- `mode=0`（按流）：`check_clw_xdr.py /xdr` → 表头 + 关键字段非空；`SEND_DIRS` 只有一个目录时**追加** `check_clw_values.py` 做值级
- `mode=1`（按事件）：`check_clw_xdr.py /xdr --event` → 事件行存在性 + 命令字语义

判定要点：

- 多目录连发 → `check_clw_values.py` **自动跳过**（"末帧"语义被后续目录帧污染）。
- 构造样包固定源端口定位协议：50000=GBT32960 / 50001=JT808 / 50002=JT808_2019 / 50003=JT809 / 50004=JT905 / 50005=JT905_2；源 IP 必须是 `192.168.1.50`（排除 clwpcap 原始流干扰）。
- clwpcap 原始样包（VIN `LFPHC7CD3S2B37616` / `LA9ECCC46GSNSD001`）走 `addc()` 单独匹配（`sport_of >= 1024`）。

## check 脚本对比

| 维度 | `ic/check_xdr_full.py` | `ns/check_xdr_full.py` | `clw/check_clw_xdr.py` |
| --- | --- | --- | --- |
| 校验粒度 | 字段必填 + 枚举 | 字段必填 + 枚举 + SM4 解密 + zip CRC +（可选）指令一致性 | 表头集合 + 关键字段非空 +（单目录）值级 |
| 第二参数 | 不支持 | `ns/data/command_baselines.json` 启用指令一致性 | `--event` 切事件模式 |
| 退出码 | 0=PASS / 1=FAIL | 0=PASS / 1=FAIL | 0=PASS / 1=FAIL |
| 错误定位 | `文件名:行号` | `文件名:行号` | 仅按协议汇总（不定位到行） |
| 必填级别 | `R` 严格必填 / `W` 规范必填空则 WARN / 空 选填 | 同左 | 关键字段非空抽查 |
| 支持的日志/协议 | `indust` / `netthreat`（其他只统计） | `cyberAttacks` / `connLog` / `payloadRusult` / `fileMonitorResult` / `dataRecognitionResult` / `flowFile` | 6 协议 |
| Python 依赖 | 标准库 | 标准库（SM4 纯 Python） | 标准库 |

字段必填级别与规则以各 check 脚本内的 `*_RULES` 表为准；需要放宽/收紧某字段校验时改规则表，不要改生成产物。**以规范文档为唯一依据**（不要凭话单样本反推）：

- icns：《工业互联网安全监测数据接口规范 V1.0》(`/home/wxs/dpi20_ice/main/InduNetSecRx/docs/product-specs/工业互联网安全监测数据接口规范-V1.0-合并版_v2.md`)
- ic：`/root/indust_test/ic/行业数据安全策略话单整理表V1.4.md`
- clw：表头集合从 `/opt/dpi_release/xdrconf/rule/indust.csv` 解析

## 场景特有坑（关键非显然事实）

### ic 特有

- **`upload.rule` 坑（最常见）**：`/root/indust_test/ic/upload.rule` 不存在时脚本不自动打开注释，**需手动 uncomment**。9 个 sftp 上报行默认全注释：数安取证/数安风险/数安识别/工控/流量监测/网络威胁/安全处置/API还原。无话单时**先看这一项**。
- **话单自动探测**（按魔数，不靠扩展名）：`.txt` 明文 / `.zip` 或 `.zip_complete` 取首个文件 / `.tar.gz` 找 `.txt` 成员。
- **`logId` 两种格式并存**：
  - A 格式（IDC3.1 多段，`ruleId` 4xxxxxxx）：省(2)+企(2)+机房(变长≥1)+设备(6)+时间(16位微秒)+随机(3)，总长 ≥ 30
  - B 格式（`yyyyMMdd` 序号，`ruleId` 5xxxxxxx，指令下发规则）：`yyyyMMdd(8)+wk_num(3)+9位序号`，共 20 位
  - 拆分从右向左：末 3 随机 → 前 16 时间 → 前 6 设备 → 前缀（省 2 企 2 机房）
- 枚举基线：`appproto` ∈ `{1..44, 9999}`；`evttype` 附录 C 大类 `{1,2,3,4,5,9,28}` + 序号，总长 ≥ 3；`isUploadFile` ∈ `{0,1}`；`eventDirection` ∈ `{0,1}`（**与 ns 的 `{1,2,3}` 不同**）。
- 字段 8~44 在 `netthreat` 大量是选填（`serialNumber/algorithm/issuer/validity/subject/StartTime/TimeLen/FileName/FileLen/Direction/FileType/ContentType`）。
- 部署：`gh_mod_switch.sh ic` 后放开 `mirror.rule` 的 `# 0033233 app.type>=0 ...` 单行注释。

### icns 特有

- **部署比 ic 多**：步骤 1.5 引擎部署（`dsmsMonitor.sh stop` → 部署 `ghnsstd` 4 个规则文件 `dsms.plcy risk.plcy ruleInfo.rc rulelib.rc` → 部署 `liboutput.so`（`/home/wxs/ds_eng/build/src/output/liboutput.so`）→ 改 `dsms.conf` `config_type=5 / isp_type=9` → `dsmsMonitor.sh start` 轮询 `pgrep engine` 90s）→ 步骤 1.8 规则部署（`RULE_SET=test|full`）→ 步骤 1.85 `cpuxsa.json` → 步骤 1.9 加速配置（`xsa.json` 流超时 3s/0.5s/3s；`xdr_template/indust_template` `sec_limit=5`；`ds_template` `sec_limit=10`；**只改运行目录，不动 ghcfg 模板**）。
- **`sync_rule_store.py` 必须**：InduNetSecRx self-heal 每 60s 用 `rule_store.db` 投影覆盖规则文件，规则库为空时拷贝的 `g_snort.rule` / `md5_black.rule` 会被清空为 0 字节 → `payloadRusult`/`fileMonitorResult` 无输出。写入前会清空库中投影落到这两个目标文件的旧规则，**仅适用于测试环境**。
- **FTP 坑**：`lftp cls -1` 在本环境返回带完整 FTP 路径前缀输出，`grep '^编译任务号_'` 永远匹配不到。脚本用 `ls` 取标准长格式 + `awk '{print $NF}'`。
- **`sessionKey.ini` 缺失时从 `ns/conf/` 兜底拷贝**（`PKCS#7` 去填充失败 = key/iv 不匹配）；密钥随 DPI 会话变化。
- **指令一致性校验跨名映射**：`payloadRusult.eventLevel ← severity`（同）；`fileMonitorResult.isPCAP ← isUploadFile`（恶意文件指令无 `isPCAP` 字段，所以要跨名）；`cyberAttacks` / `connLog` 不参与一致性校验。
- **`dataRecognitionResult` 行不能直接 `split("|")`**：`dataInfo` 内部 `|` 与分隔符冲突，必须走 `parse_data_recog_line`；段数必须 `= 13 + 3*N`，否则 `__结构__` ERROR。`attachMent` 在 `isUploadFile=0` 时**强制必填**；`assetsNum` 必须 = 各 dataContent 匹配数量加总。
- 协议代码 `PROTO_CODES` = `set(range(1, 106)) | {999}`（**注意 1~105，不是 1~103**；多了 104/105）。
- 事件分类 `EV_TYPES` = 附录 B 表 9 三级分类码（约 110 项，含 `010100/.../059900`）；`/opt/dpi/fsnortconf/rule/ns_event.txt` 必须用 icns 附录表 9 版本覆盖。
- `payloadRusult` / `fileMonitorResult` 0 条属正常；`cyberAttacks` / `connLog` / `flowFile` / `dataRecognitionResult` 才是必有。

### clw 特有

- **`/opt/dpi_release` 是真实目录**，`rm -rf` 前确认；脚本只切软链不删它。
- **脚本头部注释"不做字段校验"是过时的**——实际做了表头 + 关键字段 +（单目录）值级三层校验。
- **`clw_output_mode` 双模式**（`0`=按流 / `1`=按事件，从 `xsa.json` 读）：
  - `0`：`check_clw_xdr.py` +（单目录）`check_clw_values.py`
  - `1`：`check_clw_xdr.py --event`（事件行存在性 + 命令字语义；GBT32960 出现 `command∈{2,3}` 报"事件判定失效"；模板含 `eventType` 列时校验非零事件行 + `eventTime` 非空）
- **多目录连发 → `check_clw_values.py` 自动跳过**（"末帧"语义被污染）。
- 模板表头解析：`re.match(r"^indust2\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)", line)`，取该协议在模板里**所有列**作为 `expect`（不校验列顺序，只校验集合相等）。
- 关键字段 KEY_FIELDS（按流模式）：GBT32960 `statusChangeTrace` / `alarmFlags` / `connectId`；JT808/808_2019 `procedureType` / `encryptionRule`；JT809 `msgId` / `gnssCenterId`；JT905/905_2 `connectId` / `procedureType`。**事件模式不做关键字段非空**。
- `check_coverage.py` 是**调试工具**（不在测试脚本内调用），逐 pcap 排查"有流量无话单"。
- 不重启 engine、不动 ghcfg 模板；clw 走的是现成 `/opt/dpi_release` 环境。

## 通用排查表

| 现象 | 排查方向 |
| --- | --- |
| 等待 `start run loop` 超时 | 查 `/var/log/dpi.log` 启动/规则加载错误；确认规则文件、`sessionKey.ini`、`indust.cfg` 模块开关在位 |
| `/xdr` 无任何输出 | 发包网卡是否匹配（`send.py -i` vs 收包网卡）；`upload.rule` 该行是否被注释（ic 常见）；规则是否在位；DPI 是否真的就绪 |
| CRC 错误（ns） | `/opt/dpi/xsaconf/sessionKey.ini` 与发包侧密钥不一致，或文件传输截断 |
| `__结构__` 字段数不符 | 话单模板被改动致列错位；icns 改 csv 模板后须用 `/home/wxs/c.py` 格式化对齐列；`dataRecognitionResult` 段数需 `= 13 + 3*N` |
| `__解密__` 错误（ns） | SM4 `PKCS#7` 去填充失败 = key/iv 不匹配，检查 `sessionKey.ini` |
| 必填字段 ERROR | 对照 check 脚本规则表确认该字段是否确应必填；确认运行时实际值 |
| `cyberAttacks` 事件分类非法 `evt` | `/opt/dpi/fsnortconf/rule/ns_event.txt` 未用 icns 附录表 9 版本覆盖 |
| `eventLevel` 与指令不一致（ns） | 用 `python3 ns/gen_baselines.py` 重新生成基准；检查 `g_snort.rule` / `md5_black.rule` 是否最新 |
| icns 下 `payloadRusult` 出现输出 | 说明场景未真正切到 icns 或清空规则未生效，回查 `g_snort.rule` / `evilpkt_ioc.rule` |
| clw 无话单输出 | 检查 `WAIT_OUTPUT=300` 重试；DPI 是否在 `/opt/dpi_release`；`/xdr/indust2` 是否被其他进程占用 |
| clw `check_clw_xdr.py` 协议识别不到 | fo 按 harddecode 表输出 `JT905` 实际是 `JT905_4`；用 `PROTO_MARK[p] in line` 判定 |
| 话单 `ruleID` 在基准中未找到 | 仅提示，不影响退出码；基准清单未覆盖该指令 |

## 常用路径

- 测试脚本：`/root/indust_test/{ic,ns,clw}/test_indust_xdr.sh`
- 校验器：`/root/indust_test/{ic,ns}/check_xdr_full.py`、`/root/indust_test/ns/decode_sftp.py`（与 `ns/check_xdr_full.py` 同目录必留）、`/root/indust_test/clw/check_clw_{xdr,values,coverage}.py`
- 场景切换公共：`/root/indust_test/scene.sh`（`switch_scene_link` / `migrate_real_dpi` / `ensure_scene_config`）
- 双场景串联：`/root/indust_test/test_all.sh`（ic + icns，不含 clw）
- DPI 主进程/启停：`/opt/dpi/xsa`、`/opt/dpi/dpikill.sh`、`/opt/dpi/dpirun.sh`（clw 软链指向 `/opt/dpi_release`）
- 主日志：`/var/log/dpi.log`
- 话单输出：`/xdr/upload/{cyberAttacks,connLog,payloadRusult,fileMonitorResult,flowFile,indust,netthreat,xrt_stat_output,filter,dataidentity,datarisk,datathreat,api_file,...}/<YYYYMMDD>/`（ic/icns）；`/xdr/indust2/`（clw）
- 引擎输出：`/appslog/dsms/processResult/{indust_ns,data_recog}`（icns）
- 发包：`/root/send/`（默认集 `NS` 或 `clwpcap`，网卡 `ens11f0`）
- 场景切换：`/opt/dpi/mconf/ghcfg/gh_mod_switch.sh`（ic / icns，clw 不切）
- 场景标识：`/opt/dpi/config/rule/dpiconfig.ok`
- 会话密钥：`/opt/dpi/xsaconf/sessionKey.ini`（icns 必需）
- 规则库：`/opt/dpi/InduNetSecRxConf/rule_store.db`（icns，self-heal 投影源）
- 调试工具：`/root/indust_test/clw/check_coverage.py`（逐 pcap 排查"有流量无话单"）

## 交付结果

报告应包含：

- **当前场景标识**（`dpiconfig.ok` 内容）、脚本是否就位
- `test_indust_xdr.sh` 各步执行情况（**尤其是否检测到 `start run loop`**、发包是否完成）
- **各类话单记录数**（按场景预期输出集合比对）
- check 脚本结论（PASS/FAIL）及 **ERROR/WARN 明细**（ns/ic 包含 `文件名:行号` 定位）
- 失败时：首个 ERROR、对应话单目录/字段、可能原因、下一步排查建议

**特别提醒**（避免误报）：

- icns 下 `payloadRusult` / `fileMonitorResult` = 0 条**属正常**，不应作为失败项报告
- ic 场景若无话单**先看 `upload.rule` 注释**是否打开
- clw 场景**先确认 `clw_output_mode`** 决定走哪套校验；`check_clw_values.py` 在多目录连发时**自动跳过**不是错误
- ns 引擎本地明文 `/appslog/dsms/processResult/indust_ns` 通常 0 文件（被 `uploadfile` 守护即时搬走）
- 退出码 0 = PASS（允许 WARN），1 = FAIL（CRC 错或 ERROR）
