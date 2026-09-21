---
name: jenkins-trigger
description: '触发或查询公司 Jenkins 上的行业数安探针打包构建（MultiJob: ACT-DPI-ICE-V1.0.6.0，即本仓库 dpi20_ice 的 openEuler + ubuntu 双平台编译打包）。当用户说"触发构建"、"远程构建"、"打包"、"出包"、"冒烟包"、"构建跑完了吗"、"看构建状态/结果"等任何涉及 Jenkins 构建、编译打包的话时使用，即使用户没有明确提到 Jenkins。'
---

# Jenkins 远程构建触发（MultiJob）

## 固定参数

| 项 | 值 |
|---|---|
| Jenkins 地址 | `http://10.128.5.143:8080` |
| Job 名 | `ACT-DPI-ICE-V1.0.6.0`（MultiJob Project，行业数安探针 V1.0.6.0） |
| 认证用户 | `wangxingsi` |
| API Token | `YOUR_JENKINS_API_TOKEN` |
| Job 触发 Token | `YOUR_JENKINS_BUILD_TOKEN`（主 Job 与两个子 Job 共用） |

对应代码：`https://10.128.5.149/svn/CD1604013_DPI/branches/telecom1/dpi20_ice`（即本工作区仓库）。

## 任务编排结构

MultiJob 顺序执行两个阶段，**上一阶段 SUCCESSFUL 才会进入下一阶段**（continuationCondition=SUCCESSFUL，阶段内任一子构建 FAILURE 即终止该阶段）：

| 阶段 | 子 Job | 类型 | 编译脚本 | 节点 |
|---|---|---|---|---|
| step-1 openEuler-compile | `ACT-DPI-ICE-V1.0.6.0-OPENEULER` | MatrixProject（x86/arm 多配置） | `ice1063_compile.sh` | openEuler-x86 `10.12.130.4`、openEuler-arm `10.12.130.8` |
| step-2 ubuntu-compile | `ACT-DPI-ICE-V1.0.6.0-UBUNTU` | FreeStyleProject | `ice1063.sh` | ubuntu-x86 `10.128.5.145` |

## 产物去向

- **step-2（UBUNTU）的安装/升级包**（`main/obj/out/*`）经 FTP 插件上传到 **10.128.5.116**：
  `/01开发/ACT-POP-202601-003_数据安全管理平台V1.1.0.0/自动编译冒烟包/行业数安探针V1.0.6.0/编译任务号_<UBUNTU子Job构建号>/`
  目录里的构建号是 **UBUNTU 子 Job 自己的号**（从 MultiJob 的 subBuilds 取该子 Job 的 buildNumber），不是 MultiJob 的构建号。
- **取包**：FTP 账号 `wangxingsi` / `YOUR_FTP_PASSWORD`（密码含 `@`，用 `-u` 参数形式传，不要内嵌在 URL 里）。非交互列目录/下载：

```bash
timeout 15 lftp -u wangxingsi,'YOUR_FTP_PASSWORD' 10.128.5.116 \
  -e "ls '/01开发/ACT-POP-202601-003_数据安全管理平台V1.1.0.0/自动编译冒烟包/行业数安探针V1.0.6.0/'; bye"
```

  本机另有交互式快捷脚本 `/root/lftp.sh`。
- **step-1（OPENEULER）不上传 FTP**（无构建后插件），只编译。
- 两个子 Job 编译的 .so 库文件都会由 `rdmpublic` 账号自动 svn commit 回本仓库（即 git log 中 `[其它] 编译产物提交` 的来源）：openEuler → `output/binopenEuler_22_03/{x86,arm}/`，ubuntu → `output/binUbuntu_20_04/x86/`；UBUNTU 阶段还会自动提交版本号文件 `main/ver.h、svnver、subver、mainver`。本地 git svn rebase 时会拉到这些自动提交。

全流程约 1 小时。

## 触发前必查（重要）

该 Job **允许并发构建（concurrentBuild=true）**，重复触发不会排队而是并行执行，会同时占用同一批编译节点、互相干扰。触发前必须先确认没有在跑的构建：

```bash
curl -s --noproxy '*' --connect-timeout 5 \
  -u "wangxingsi:YOUR_JENKINS_API_TOKEN" \
  "http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0/lastBuild/api/json" | jq '{number, result, building}'
```

若 `building: true`，先告知用户当前构建号和进度，由用户决定是否仍然触发。

## 触发构建

```bash
curl -s --noproxy '*' --connect-timeout 5 -D - -o /dev/null -X POST \
  -u "wangxingsi:YOUR_JENKINS_API_TOKEN" \
  "http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0/build?token=YOUR_JENKINS_BUILD_TOKEN&cause=%E6%89%93%E5%8C%85%E6%9E%84%E5%BB%BA"
```

关键点：

- **必须加 `--noproxy '*'`**。本机 shell 的 `http_proxy` 指向 `10.12.186.252:7890`，且 curl 是 7.68、不支持 `no_proxy` 的 CIDR 网段写法，不加此参数请求会挂在代理上直到超时。
- 成功标志：`HTTP/1.1 201 Created`，响应头 `Location: .../queue/item/N/` 是排队号，不是最终构建号。
- `cause` 参数可选，为 URL 编码文本（示例为"打包构建"），会显示在构建历史的触发原因里，中文需自行编码。
- `403` = token 或认证错误；`404` = Job 路径不对。
- 该 MultiJob **非参数化**，只能用 `/build`；不要使用 `buildWithParameters`，也不要附加自定义参数。

### 单独触发子 Job

两个子 Job 也已开启远程触发，token 与主 Job 相同（Job 名换成 `-OPENEULER` 或 `-UBUNTU`）：

```bash
curl -s --noproxy '*' --connect-timeout 5 -X POST \
  -u "wangxingsi:YOUR_JENKINS_API_TOKEN" \
  "http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0-UBUNTU/build?token=YOUR_JENKINS_BUILD_TOKEN"
```

注意：单独触发子 Job 只编译对应平台，但产物副作用照常发生（svn commit 库文件回仓库；UBUNTU 还会 FTP 上传，目录按它自己的构建号 +1）；OPENEULER 是矩阵项目，一次触发会 x86/arm 两配置并行。MultiJob 正在跑时不要单独触发子 Job，会抢占同一批编译节点。

## 确认已开始

触发后等 3 秒左右再查 `lastBuild`，`number` 比之前 +1 且 `building: true` 即已开始。**并发风险下 lastBuild 可能不是自己触发的那次，最好记下触发前的 number，+1 即本次**。

## 查询进度与结果

```bash
# MultiJob 总进度（含各阶段子构建明细 subBuilds）
curl -s --noproxy '*' --connect-timeout 5 \
  -u "wangxingsi:YOUR_JENKINS_API_TOKEN" \
  "http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0/106/api/json" \
  | jq '{building, result, subBuilds: [.subBuilds[]? | {jobName, buildNumber, result, phaseName}]}'
```

- `subBuilds` 里能看到当前跑到哪个阶段（phaseName）、对应子 Job 的构建号和结果。
- **三个 Job 的构建号是独立序列，永远对不齐**（MultiJob #106 ↔ OPENEULER #112 ↔ UBUNTU #90 各自计数），对应关系以 `subBuilds` 为准，不要拿主构建号去猜子构建。反查（知道子构建号找主构建）用子构建的 causes：

```bash
curl -s --noproxy '*' --connect-timeout 5 \
  -u "wangxingsi:YOUR_JENKINS_API_TOKEN" \
  "http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0-OPENEULER/112/api/json" \
  | jq '[.actions[] | select(._class=="hudson.model.CauseAction") | .causes[]? | {upstreamProject, upstreamBuild}]'
```

  返回 `upstreamProject` + `upstreamBuild` 即所属 MultiJob 构建号；FTP 取包目录用的是 **UBUNTU 子构建号**（subBuilds 里的 buildNumber）。
- step-1 失败时整个 MultiJob 直接结束，不会跑 step-2。
- 查具体子构建详情（如 OPENEULER 矩阵各配置 x86/arm 的独立结果）：

```bash
curl -s --noproxy '*' --connect-timeout 5 \
  -u "wangxingsi:YOUR_JENKINS_API_TOKEN" \
  "http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0-OPENEULER/112/api/json" \
  | jq '{building, result, runs: [.runs[]? | {url, result}]}'
```

- `building: true` 还在跑；`result: "SUCCESS"` 成功；`"FAILURE"` 失败（`"UNSTABLE"`/`"ABORTED"` 同理）。
- 全流程约 1 小时，不要频繁轮询。

## 回复用户的固定信息

触发成功后向用户提供：

- MultiJob 构建页：`http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0/<构建号>/`
- 控制台日志：`http://10.128.5.143:8080/job/ACT-DPI-ICE-V1.0.6.0/<构建号>/console`
- 失败排查时先看是哪个阶段：step-1 看子 Job `-OPENEULER`（注意矩阵项目下 x86/arm 各有独立 run 日志），step-2 看 `-UBUNTU`。
