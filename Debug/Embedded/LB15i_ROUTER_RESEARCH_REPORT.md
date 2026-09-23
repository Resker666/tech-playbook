# LB15i / ASR1803 路由器调试与固件分析复盘

> 文档日期：2026-09-16  
> 目标设备：LB15i 随身路由器（硬件 `LB15I_N12`）  
> 固件版本：`LB15iKAS01213_N12_LED_V002`  
> 平台：ASR1803 / Nezha MIFI  
> 分析环境：Windows、PowerShell、Python 3、USB RNDIS、COM3/COM4  
> 文档目的：记录本次实际执行过程、证据、踩坑点、可复用方法、当前能力边界与学习路线。

## 1. 使用范围与安全说明

本文面向设备所有者、固件研究人员和嵌入式开发者。所有操作应仅用于自己拥有或明确获准测试的设备。

本文已经脱敏，不记录以下内容：

- Wi-Fi 密码、管理密码；
- IMSI、ICCID、IMEI 等蜂窝身份信息；
- 用户 Cookie、会话令牌；
- 可能出现在 PSM/NVM 中的个人数据。

危险命令即使在固件中被发现，也不等于应该执行。射频校准、EFUSE、NVM 写入、闪存写入、下载模式、崩溃模式和未知 DIAG 帧都有导致设备掉网、失去校准数据或变砖的风险。

## 2. 一页结论

### 2.1 最重要的结论

这台设备的主系统不是常见的 Linux/OpenWrt，而是 ThreadX/Nucleus 风格的 RTOS 固件。因此：

- 没有常规 Linux `root` 用户；
- 没有 `/bin/sh`、BusyBox 或可登录的 SSH shell；
- 网页中的 Telnet 配置项是遗留模板，打开配置并不会启动 Telnet 服务；
- COM3 是 AT 控制口；
- COM4 是 ASR ICAT/DIAG 二进制诊断口，不是文本终端；
- 可以使用 AT 命令和隐藏的 AIC8800 Wi-Fi 工程控制台；
- 若要获得更深层控制，应走 DIAG、厂商工具、固件逆向或定制固件路线，而不是继续寻找 Linux root 密码。

### 2.2 已经能做到的事情

- 登录并分析 Web 管理界面及隐藏 XML 接口；
- 通过 COM3 执行 AT 命令；
- 安全重启模组；
- 查询蜂窝状态、信号和固件信息；
- 进入隐藏的 AIC8800 Wi-Fi 工程控制台并执行只读查询；
- 获取并校验 8 MiB 全闪存镜像；
- 解析 Marvell/ASR TIM 镜像表；
- 解压 OSLO、GRBI、RFBN 中的 17 个 LZMA 数据流；
- 恢复 OSLO 各段的真实虚拟地址；
- 反汇编 ARM Thumb 代码并恢复 PC 相对交叉引用；
- 自动提取 310 条 AT 命令及处理函数地址；
- 验证 COM4 的 DIAG 输出受 ICAT/CATStudio 握手控制；
- 在实验后恢复诊断日志关闭状态，并验证 SSH/Telnet/ADB 未开放。

### 2.3 目前还做不到的事情

- 不能通过 SSH/Telnet 获得 Linux root shell，因为 stock 固件本身不是 Linux；
- 没有 CATStudio 握手和匹配数据库时，不能直接解码 COM4；
- 尚未完整恢复 ASR ICAT 主机侧协议；
- 尚未验证固件重打包、校验、签名和安全刷回流程；
- 没有恢复方案前，不应写闪存或修改射频/NVM 数据。

## 3. 设备与连接拓扑

本次使用的连接方式如下：

```text
互联网
  │
手机热点
  │
Windows 分析主机
  ├── USB RNDIS ── 192.168.0.1（路由器 Web 管理）
  ├── COM3 ─────── Mobile AT Interface
  └── COM4 ─────── Mobile Diag Interface
```

先让分析主机使用手机热点上网，是一个很重要的准备动作。这样重启路由器或释放 RNDIS 地址时，不会让远程协作、资料检索或分析会话同时中断。

USB 复合设备枚举结果：

| 接口 | Windows 端口 | 作用 |
|---|---:|---|
| MI_00 | RNDIS 网卡 | Web 管理与局域网数据 |
| MI_02 | COM4 | Mobile Diag Interface，ICAT/DIAG 二进制通道 |
| MI_04 | COM3 | Mobile AT Interface，AT 命令通道 |

USB CDC 上标注的 115200 波特率通常不是实际 USB 传输速率，但串口工具仍可按 115200、8N1、无流控进行配置。

## 4. 完整执行过程

### 4.1 建立不会因路由器重启而断开的分析环境

最初的风险是：分析主机本身依赖目标路由器联网，一旦执行重启或 USB 模式切换，分析过程也会被切断。

采取的措施：

1. 让 Windows 主机连接手机热点；
2. 保留路由器 USB 连接用于 RNDIS、COM3 和 COM4；
3. 在操作前确认默认互联网出口不再依赖目标路由器；
4. 再执行重启和串口监听。

可复用原则：控制通道、数据通道和自己的互联网出口尽量相互独立。

### 4.2 Web 管理面与网络服务检查

管理地址：

```text
http://192.168.0.1/
```

初始服务检查结果：

| TCP 端口 | 结果 | 解释 |
|---:|---|---|
| 80 | 开放 | Web 管理界面 |
| 22 | 关闭/拒绝 | 没有 SSH 服务 |
| 23 | 关闭/拒绝 | 没有正在监听的 Telnet 服务 |
| 5555 | 关闭/拒绝 | 没有网络 ADB 服务 |

这里应区分三种情况：

- 超时：可能被防火墙丢弃；
- 主动拒绝：目标主机可达，但没有进程监听；
- 连接成功：端口上确实有服务。

本设备的 22、23、5555 属于没有服务监听，而不是单纯被网页隐藏。

### 4.3 隐藏 Telnet XML 接口实验

在网页资源中发现了隐藏接口：

```text
/xml_action.cgi?method=get&module=duster&file=control_telnet
```

使用 XML 请求可以读取或写入类似下面的配置：

```xml
<?xml version="1.0" encoding="US-ASCII"?>
<RGW>
  <enable_telnet>1</enable_telnet>
</RGW>
```

实验步骤：

1. 读取当前值；
2. 经用户授权写入 `enable_telnet=1`；
3. 重启设备；
4. 再次读取，确认配置值确实保存为 `1`；
5. 检测 TCP 23；
6. TCP 23 仍然主动拒绝连接；
7. 将 `enable_telnet` 恢复为 `0`；
8. 再次确认 23 端口关闭。

结论：

`control_telnet` 是 Web/Duster 层保留的配置模板，不代表主固件内有 Telnet 守护进程。后续对解压固件进行字符串和命令表检索，也没有发现 Telnet 服务实现；真实代码中唯一普通 `telnet` 文本出现在运营商 APN `airtelnet.es`，与远程登录无关。

### 4.4 隐藏 diagnostic XML 接口实验

另一个隐藏 XML 文件能够接收类似：

```xml
<command>id</command>
```

观察结果：

- Web 层会保存该字符串；
- 没有命令输出；
- 没有可观察到的系统行为；
- 清空请求甚至不会正常清除已保存的字符串。

结论：这是配置占位或未接入执行器的遗留接口，不是命令注入或系统 shell。

### 4.5 识别 COM3 与 COM4

Windows USB 描述符给出了明确证据：

```text
COM3  Mobile AT Interface
COM4  Mobile Diag Interface
```

实际验证：

- COM3 发送 `AT` 返回 `OK`；
- COM3 可以查询 `AT+CSQ`；
- COM4 用文本方式打开没有 shell 提示符；
- COM4 不响应普通 AT 命令。

因此 COM4 不能当作 UART shell 猜波特率，它是独立的二进制诊断协议端口。

### 4.6 AT 命令探测

已执行并验证的典型命令：

| 命令 | 结果 | 用途/结论 |
|---|---|---|
| `AT` | `OK` | AT 通道健康检查 |
| `AT+CSQ` | 返回信号值 | 蜂窝信号查询 |
| `AT+CFUN=1,1` | 接受并重启 | 安全重启模组 |
| `AT+CLAC` | `ERROR` | 固件不提供标准命令列表 |
| `AT+MIFIUSBMODE=W,1` | `OK`，USB 组合未变化 | `OK` 不等于预期效果发生 |
| `AT+LOG=?` | `+LOG: (0: FLASH)` | 存在私有日志命令 |
| `AT+LOG?` | 仅 `OK` | 查询不返回当前状态 |
| `AT+FSLOG=?` | `+FSLOG` | 存在文件系统日志命令 |
| `AT+FSLOG?` | 仅 `OK` | 无可读状态 |
| `AT+QDUMPCFG=?` | `ERROR` | 本固件未注册 Quectel 的同名命令 |

固件字符串中还发现内部使用的命令：

```text
AT+LOG=17,2
AT+LOG=17,255
AT+LOG=57,2
AT+LOG=59,4
AT+LOG=59,8
AT+LOG=59,12
```

这些值只作为固件行为线索，没有全部在设备上执行。

### 4.7 COM4 与 `AT+LOG=19,1` 实验

厂商 ASR 平台资料建议使用 CATStudio 连接 DIAG 口，并在部分情形下使用：

```text
AT+LOG=19,1
```

本次采用了最小变量实验：

1. 打开 COM4，采集 2 秒静默基线；
2. COM3 发送 `AT+LOG=19,1`；
3. 保持 COM4 打开，采集 8 秒；
4. COM3 发送 `AT+CSQ` 制造一次正常活动；
5. 再采集 COM4 约 2.5 秒；
6. 最后发送 `AT+LOG=19,0` 恢复。

实际结果：

```text
BaselineBytes   : 0
EnableResponse  : OK
ProbeResponse   : +CSQ: 23,99 / OK
CapturedBytes   : 0
DisableResponse : OK
```

结论：

- `AT+LOG=19,1` 确实被固件接受；
- 但打开日志开关不足以让 COM4 自动吐数据；
- 固件中的 `isDiagConnected`、`diagICATreadyCMM`、`diagMasterCMM` 等字符串说明输出受 ICAT 主机会话控制；
- CATStudio 打开端口时应先发送握手和过滤器配置；
- 没有握手时 COM4 完全静默是符合实现逻辑的。

官方参考：

- [Quectel ASR 平台 Log 工具使用说明](https://developer.quectel.com/doc/quecpython/Application_guide/zh/dev-tools/LogTool/ASR.html)

该文档说明 ASR DIAG 口应由 CATStudio/QWinLog 使用，解析日志还需要与固件匹配的 DB/MDB 文件。

### 4.8 获取并校验闪存镜像

已保存全闪存镜像：

```text
E:\develop\github\LB15i_flash_20260915_2315.bin
```

属性：

```text
大小：8 MiB
SHA-256：1e15521959ed0943def2b070f39dc4b4e10eda6f69768246eb7a79e12d1d2ad8
```

说明：当前保留的自动化脚本中没有完整记录最初生成该镜像的逐字采集命令，因此本文不伪造一个“原始采集步骤”。复用本流程时，应优先使用厂商升级/下载工具的只读功能、硬件编程器或经过验证的读闪存命令，并在任何修改前至少保存两份校验一致的备份。

校验方法：

```powershell
Get-FileHash 'E:\develop\github\LB15i_flash_20260915_2315.bin' -Algorithm SHA256
```

### 4.9 识别 TIM/NTIM 镜像结构

闪存起始处包含 Marvell 风格的 TIM/NTIM 头和镜像描述表。解析到的主要条目：

| 标识 | Flash 偏移 | 加载地址 | 区域大小 |
|---|---:|---:|---:|
| TIMH | `0x000000` | `0xD1000000` | `0x000F50` |
| OBMI | `0x006000` | `0x07800000` | `0x019994` |
| RBLI | `0x020000` | `0x07C4F000` | `0x010000` |
| OSLO | `0x040000` | `0x06000000` | `0x410000` |
| GRBI | `0x450000` | `0x07E40000` | `0x0D0000` |
| RFBN | `0x520000` | `0x07A00000` | `0x010000` |
| NTLZ | `0x530000` | `0x07380000` | `0x010000` |

相关参考：

- [Marvell PXA3xx/Tavor Boot ROM Reference Manual](https://docs.toradex.com/100203-colibri-arm-som-pxa3xx-tavor-p-boot-rom-ref-manual.pdf)
- [公开的 ASR/Air720 固件结构分析](https://luatdoc.papapoi.com/482/)

### 4.10 解压多段 LZMA

OSLO、GRBI、RFBN 并不是一个连续的单流压缩包，而是在 4 KiB 对齐位置存放多个 LZMA-Alone 流。

提取脚本：

```text
E:\develop\github\LB15i_analysis\extract_lzma_segments.py
```

执行：

```powershell
python 'E:\develop\github\LB15i_analysis\extract_lzma_segments.py'
```

结果：

| 区域 | 流数量 | 解压后合计 |
|---|---:|---:|
| OSLO | 10 | 8,271,580 字节 |
| GRBI | 6 | 1,835,008 字节 |
| RFBN | 1 | 32,768 字节 |

共 17 个 LZMA 流，均验证到解码器 EOF，且解压大小与 LZMA 头中声明值一致。

清单：

```text
E:\develop\github\LB15i_analysis\extracted\manifest.json
```

### 4.11 判断主系统类型

OSLO 解压内容中发现：

```text
SW_PLATFORM=LWG_FALCON_MIFI_CUST_THREADX_DEV2 ... SRCNUCLEUS ... DIAGOSHMEM ...
ThreadX
Nucleus
diag_comm_EXTif_OSA_NUCLEUS.c
```

同时没有发现 Linux 常见组成：

- ELF 用户态根文件系统；
- `/bin/sh` 或 BusyBox applet；
- `sshd`、`dropbear`、`telnetd`；
- Linux init/systemd/OpenRC；
- `/etc/passwd` 对应的登录体系。

固件中的 `sac_shell.c` / `sac_shell_engine.c` 是蜂窝协议栈内部所谓 shell/engine 模块名，不是用户可交互的命令 shell。

因此“继续找 root 密码”的方向被证据否定，应切换到 RTOS 工程接口与固件逆向思路。

### 4.12 恢复 OSLO 真实虚拟地址

最初把 10 个 OSLO 解压段直接拼接成一个文件，虽然可以搜索字符串，但绝对指针交叉引用几乎全部失败。

原因：每个段在 RAM 中并不是首尾紧挨，而是由 OSLO 加载器放到不同虚拟地址，中间有间隙。

从 OSLO 前部加载表恢复的基址：

```text
0x06002000
0x060E2000
0x061E2000
0x062C2000
0x063C2000
0x064A2000
0x065E2000
0x066D2000
0x067A2000
0x068E6990
```

验证例子：

- `at+wifi=cmdline` 位于第 7 个段内部；
- 按真实基址映射后得到虚拟地址 `0x066B670C`；
- 在 AT 注册表中找到了唯一绝对指针引用 `0x0690AE6C`；
- 由此定位到处理函数 `0x06629B18`。

映射工具：

```text
E:\develop\github\LB15i_analysis\oslo_map.py
```

示例：

```powershell
python 'E:\develop\github\LB15i_analysis\oslo_map.py' 'at+wifi=cmdline' --context 0x100
```

### 4.13 ARM Thumb 反汇编与 PC 相对引用

使用 Capstone 5.0.6 进行 ARM Thumb 反汇编。库安装在项目内的 `vendor` 目录，没有改动系统 Python：

```text
E:\develop\github\LB15i_analysis\vendor
```

Thumb 固件经常使用以下方式引用字符串：

- 绝对地址字面量；
- `ADR`；
- `ADDW reg, PC, #imm`；
- `SUBW reg, PC, #imm`；
- literal pool；
- 函数指针表。

只搜索四字节绝对指针会漏掉大量引用，因此编写了 PC 相对扫描器：

```text
E:\develop\github\LB15i_analysis\find_pcrel_xrefs.py
```

PowerShell 示例：

```powershell
$env:PYTHONPATH='E:\develop\github\LB15i_analysis\vendor;E:\develop\github\LB15i_analysis'
python 'E:\develop\github\LB15i_analysis\find_pcrel_xrefs.py' 0x065E3284 --window 0xA0
```

### 4.14 自动提取 AT 命令注册表

AT 表每条记录包含命令名、参数数量、帮助字符串和处理函数指针。编写脚本自动扫描并验证这些字段：

```text
E:\develop\github\LB15i_analysis\extract_at_table.py
```

执行：

```powershell
python 'E:\develop\github\LB15i_analysis\extract_at_table.py'
```

输出：

```text
E:\develop\github\LB15i_analysis\at_command_table.csv
```

共提取 310 条命令。

重点结果：

- 没有 SSH、Telnet、ADB、shell、console 命令；
- 存在日志、闪存读取、工程测试、射频和 NVM/MRD 命令；
- 存在隐藏的 `+wifi` 字符串转发入口；
- 存在 `*READFLASH`、`*REGRW`、`+FLASHBP` 等高风险工程能力；
- 高风险能力只做了静态确认，没有执行写入或射频校准。

### 4.15 隐藏 AIC8800 Wi-Fi 工程控制台

查询：

```text
AT+WIFI=?
```

固件返回：

```text
at+wifi=cmdline
OK
```

进入入口：

```text
AT+WIFI=CMDLINE
```

返回 `OK`，同时普通 `AT` 仍然正常，说明它不是把 COM3 永久切换为另一个串口，而是把字符串转发给 AIC8800 Wi-Fi 子系统。

通过静态分析恢复的只读子命令，并在设备上验证：

| 命令 | 返回示例 | 作用 |
|---|---|---|
| `AT+WIFI=info` | Wi-Fi 固件版本、芯片/模式信息 | 查询子芯片版本 |
| `AT+WIFI=stanum` | `n:0` | 查询关联 STA 数量 |
| `AT+WIFI=stainfo` | `sta:n:0` | 查询 STA 信息 |
| `AT+WIFI=temp` | `get chip temp: 44` | 查询芯片温度，数值会随环境变化 |
| `AT+WIFI=sdio` | `sdio free cnt: 40` | 查询 SDIO 资源状态 |

发现但没有执行的高风险/改变状态子命令包括：

```text
aicrftest
rfmode
shut
dpd
射频、制造、校准相关命令
```

这一工程控制台只管理 AIC8800 Wi-Fi 子芯片，不是主 RTOS shell。

### 4.16 DIAG 协议静态分析

固件中确认存在：

```text
diagICATreadyCMM
diagMasterCMM
diag_CommTransmitToUsb
Rcv diag cmd
isDiagConnected
SPLIT_FILTER_STATE_REPORT_ENABLE_ALL
```

已恢复的部分协议特征：

- 外部消息存在固定头部；
- 代码通过偏移 `0`、`1`、`2`、`4` 读取类型、子类型、16 位字段和 32 位字段；
- 有效载荷从偏移 `12` 开始；
- USB 接收支持分片重组；
- 首字节高位被用作方向/请求类标志；
- 内部控制消息有约 12 类分发路径；
- `ICAT ready` 是内部 CMM 事件名，不能直接把字符串当作 USB 握手帧发送。

由于服务 ID、过滤器消息和完整校验语义尚未恢复，没有向 COM4 盲发构造数据。正确的下一步是：用可信 CATStudio 建立连接，同时用 USBPcap/Wireshark 捕获主机发送的第一批帧，再与反汇编对应。

### 4.17 最终状态恢复与验证

最后执行：

```text
AT+LOG=19,0
AT
```

均返回 `OK`。

最终网络状态：

```text
Web 80     : Open
SSH 22     : Closed
Telnet 23  : Closed
ADB 5555   : Closed
```

最终验证脚本：

```text
E:\develop\github\LB15i_analysis\verify_final_state.ps1
```

## 5. 踩过的坑与原因

### 坑 1：配置值成功保存，不代表功能存在

`enable_telnet=1` 可以写入并在重启后读回，但端口 23 始终没有服务监听。

经验：验证功能必须观察最终行为，例如端口、进程、协议握手或真实输出，不能只看配置页面。

### 坑 2：`OK` 不等于目标效果已经发生

`AT+MIFIUSBMODE=W,1` 和 `AT+LOG=19,1` 都返回 `OK`，但前者没有改变 USB 组合，后者也没有让 COM4 自动输出。

经验：AT 的 `OK` 往往只表示解析器接受了命令。

### 坑 3：COM 口名称相似，但协议完全不同

COM3 是文本 AT，COM4 是二进制 DIAG。把 COM4 当普通串口终端会得到“完全没输出”的假象。

经验：先看 USB interface number、设备描述和端点用途，再选择工具。

### 坑 4：日志开关与主机连接状态是两个条件

`AT+LOG=19,1` 只控制日志侧状态，DIAG 发送仍受 `isDiagConnected` 和 ICAT 握手控制。

经验：很多工程协议是“设备开关 + 主机注册/过滤器”双条件。

### 坑 5：直接拼接解压段会破坏虚拟地址关系

拼接文件适合搜索字符串，不适合交叉引用。段间空洞被删除后，所有后续地址都偏移。

经验：固件逆向必须保留 load address、VMA、段边界和对齐信息。

### 坑 6：只搜绝对指针会漏掉 Thumb 的 PC 相对引用

DIAG 日志字符串主要通过 `ADR` 或 `ADDW/SUBW PC` 引用，因此普通四字节指针扫描返回空。

经验：ARM/Thumb 逆向时应同时处理 literal pool 和 PC-relative addressing。

### 坑 7：字符串里的 `shell` 不一定是交互式 shell

`sac_shell.c` 看起来很诱人，但上下文表明它属于蜂窝协议栈内部状态机。

经验：字符串是线索，不是结论；必须追交叉引用、调用者和输入输出路径。

### 坑 8：线性反汇编会把嵌入数据当代码

代码段中混有字符串、字面量池和表格，Capstone 会显示大量看似奇怪的指令。

经验：启用 skip-data、从已知函数入口反汇编，并用控制流和引用交叉验证。

### 坑 9：PowerShell 空字节数组可能变成 `$null`

第一版 COM4 采集函数在没有任何字节时，函数返回值被 PowerShell 展开成 `$null`，导致 `WriteAllBytes` 报错。

修复方式：

```powershell
return ,$result.ToArray()
```

一元逗号可以确保空数组作为一个对象返回。

### 坑 10：公开软件下载不等于可信来源

CATStudio 在文档中被确认存在，但厂商通常要求通过技术支持获取。搜索结果中的论坛和网盘包不能直接信任。

经验：工程工具可接触串口、USB 和固件，必须优先官方来源，并检查签名、哈希和隔离运行环境。

### 坑 11：不要把恢复手段放到最后考虑

下载模式、闪存写入或校准修改一旦出错，设备可能无法通过当前 USB 方式恢复。

经验：刷写前先确认 BootROM 下载模式、驱动、完整镜像、物理 UART/BOOT 点和可重复恢复流程。

## 6. 可复用研究流程

以下流程适用于类似的蜂窝路由器、CPE、随身 Wi-Fi 和复合 USB 模组。

### 阶段 0：授权与边界

1. 确认设备所有权或测试授权；
2. 明确哪些动作可以做：只读、重启、配置修改、刷写；
3. 禁止先试未知写命令；
4. 建立脱敏规则。

### 阶段 1：确保分析通道独立

1. 使用备用互联网连接；
2. 将管理网与互联网出口分开；
3. 记录设备重启后的重新枚举时间；
4. 准备本地串口日志。

### 阶段 2：枚举攻击面与管理面

1. Web 页面和静态资源；
2. 隐藏 CGI/XML/JSON 接口；
3. TCP/UDP 服务；
4. USB interface、COM 口、RNDIS/MBIM；
5. 物理 UART、BOOT/下载测试点；
6. 升级包和恢复工具。

### 阶段 3：先做无副作用查询

推荐顺序：

```text
AT
ATI
AT+CGMR
AT+CSQ
命令的 ? / =? 查询形式
```

每次记录：

- 命令原文；
- 返回内容；
- 执行前后 USB/网络状态；
- 是否持久化；
- 恢复命令。

### 阶段 4：建立实验基线

任何功能实验都使用同一模板：

1. 采集操作前基线；
2. 只改变一个变量；
3. 记录直接返回；
4. 观察最终效果；
5. 执行恢复命令；
6. 再次验证状态。

### 阶段 5：先备份，再逆向

1. 获取完整镜像；
2. 计算 SHA-256；
3. 复制到只读备份位置；
4. 解析启动头和分区表；
5. 再处理压缩、文件系统或代码。

### 阶段 6：保留内存映射

提取固件时同时保存：

- Flash offset；
- compressed size；
- uncompressed size；
- load address/VMA；
- SHA-256；
- 段顺序与对齐。

### 阶段 7：静态分析优先于盲发命令

1. 搜索帮助字符串；
2. 定位命令注册表；
3. 获取 handler 地址；
4. 反汇编参数解析逻辑；
5. 判断是读、写、重启、射频还是闪存操作；
6. 只对确认安全的只读分支做动态验证。

### 阶段 8：专有协议采用“工具抓包 + 固件对照”

对 COM4/DIAG 这类协议：

1. 获取可信厂商工具；
2. 用 USBPcap 捕获连接过程；
3. 找到首个主机请求和设备响应；
4. 对照固件接收解析函数；
5. 逐字段恢复帧结构；
6. 最后才编写最小客户端。

### 阶段 9：收尾验证

至少验证：

- 临时日志已关闭；
- 调试服务未意外开放；
- 网络与 AT 口仍正常；
- 配置恢复到预期状态；
- 没有未保存的设备身份/校准更改。

## 7. 现有脚本与用途

| 文件 | 用途 |
|---|---|
| `extract_lzma_segments.py` | 扫描并解压 OSLO/GRBI/RFBN 的 LZMA-Alone 流 |
| `xref_strings.py` | 早期连续镜像绝对指针搜索，保留作简单场景参考 |
| `oslo_map.py` | 按真实 VMA 定位字符串和绝对引用 |
| `find_pcrel_xrefs.py` | 搜索 Thumb PC 相对字符串引用与直接调用 |
| `extract_at_table.py` | 自动提取 AT 命令表并输出 CSV |
| `query_debug_at.ps1` | 查询隐藏调试命令帮助和状态 |
| `capture_diag_log19.ps1` | 建立 COM4 基线、临时开日志、抓取并恢复 |
| `probe_wifi_cmdline.ps1` | 验证隐藏 AIC8800 Wi-Fi 工程命令 |
| `verify_final_state.ps1` | 关闭 DIAG 日志并验证 AT/网络端口状态 |

所有文件位于：

```text
E:\develop\github\LB15i_analysis
```

## 8. 当前可以直接使用的操作

### 8.1 AT 口健康检查

使用 COM3，115200、8N1、无流控，命令以回车结束：

```text
AT
AT+CSQ
```

### 8.2 安全重启

```text
AT+CFUN=1,1
```

重启会让 USB 设备短暂消失并重新枚举。

### 8.3 Wi-Fi 子芯片只读查询

```text
AT+WIFI=CMDLINE
AT+WIFI=info
AT+WIFI=stanum
AT+WIFI=stainfo
AT+WIFI=temp
AT+WIFI=sdio
```

不要在不知道含义时执行 `rfmode`、`aicrftest`、`shut`、校准和制造命令。

### 8.4 离线重新提取与分析

```powershell
python 'E:\develop\github\LB15i_analysis\extract_lzma_segments.py'
python 'E:\develop\github\LB15i_analysis\extract_at_table.py'
python 'E:\develop\github\LB15i_analysis\oslo_map.py' '+WIFIDBG' --context 0x80
```

## 9. 后续可行路线

### 路线 A：取得 CATStudio 与匹配数据库

优先级最高、风险最低。

需要向设备/模组厂家索取：

- CATStudio 或 QWinLog；
- 与 `LB15iKAS01213_N12_LED_V002` 精确匹配的 DBG/MDB/TXT 数据库；
- 对应 ASR1803/Nezha MIFI 的 USB 驱动；
- 若有，完整升级包和 release notes。

拿到后可以：

1. 连接 COM4；
2. 验证 ICAT 握手；
3. 抓取 AP/CP 日志；
4. 导出原始日志；
5. 用 USBPcap 分析握手；
6. 逐步实现开源最小采集器。

### 路线 B：恢复 ICAT/DIAG 协议

已有基础：

- 固定头字段已部分识别；
- 分片重组逻辑已定位；
- ICAT ready 内部分发已定位；
- USB 发送/接收函数已定位。

仍需解决：

- 服务 ID；
- 主机注册流程；
- 过滤器格式；
- 长度/校验语义；
- DB 文件格式与消息 ID 映射。

### 路线 C：定制 RTOS 固件

这是高风险路线，不能直接把 OpenSSH“装进去”。可能的目标是增加自定义 AT/DIAG 命令或调试服务。

前置条件：

1. 理解 TIM 哈希/签名验证；
2. 能重新压缩并保持段布局；
3. 理解 OSLO 启动加载表；
4. 有 BootROM 下载/编程器恢复方案；
5. 能在 RAM 或仿真环境验证补丁；
6. 明确不会破坏蜂窝射频校准和合法标识。

### 路线 D：寻找物理调试接口

如果拆机，可调查：

- Boot UART TX/RX/GND；
- BOOT strap；
- SWD/JTAG 测试点；
- SPI NAND/NOR 引脚；
- USB BootROM 枚举模式。

所有探测先使用逻辑分析仪/示波器确认电平，避免直接连接 5V 串口。

## 10. 可以从本次研究学到什么

### 10.1 网络与服务验证

你可以学会区分“网页里有开关”“配置保存成功”和“真正有服务监听”这三个层次。最终验证必须落在 TCP 连接、协议响应或实际进程行为上。

### 10.2 USB 复合设备

同一根 USB 线可以同时承载网卡、AT 串口和 DIAG 串口。Interface number、设备描述和驱动绑定决定每个端口的真实用途。

### 10.3 AT 命令体系

可以学习：

- 执行命令、查询命令、测试命令的区别；
- `OK`/`ERROR` 的语义边界；
- URC 与同步响应；
- 私有 AT 注册表；
- 如何从 handler 反推参数类型和取值范围。

### 10.4 RTOS 与 Linux 的区别

Linux 路由器常见的是进程、文件系统、用户和 shell；RTOS 固件常见的是静态链接任务、消息队列、固定命令表和厂商 DIAG。两者的“后台”概念完全不同。

### 10.5 固件容器与启动链

可以学习 TIM/NTIM、镜像标识、Flash offset、load address、启动跳转、压缩段和校验之间的关系。

### 10.6 LZMA 与二进制提取

可以学习如何：

- 识别 LZMA-Alone 头；
- 读取声明的解压大小；
- 使用流式解码器判断真实压缩长度；
- 验证 EOF 和输出大小；
- 为每个段计算哈希。

### 10.7 ARM Thumb 逆向

本案例覆盖：

- Thumb 函数指针最低位；
- literal pool；
- `ADR` 与 PC 相对寻址；
- 命令注册表；
- jump table；
- 字符串交叉引用；
- 代码与数据混排。

### 10.8 专有协议逆向

最有效的方法不是猜帧，而是把三类证据合起来：

```text
厂商工具抓包 + 固件接收函数 + 可控设备实验
```

每次只改变一个字段，建立基线并准备恢复路径。

### 10.9 工程安全与研究伦理

真正专业的逆向并不是“尽可能多地执行危险命令”，而是知道哪些证据已经足够、哪些动作需要额外授权、哪些状态必须恢复，以及如何避免泄露设备身份和用户数据。

## 11. 建议学习顺序

如果希望自己继续深入，可以按以下顺序学习：

1. TCP/IP、端口扫描和 HTTP/XML 请求；
2. 串口基础、USB CDC 与复合设备；
3. 3GPP 常用 AT 命令；
4. Python 二进制解析：`struct`、`lzma`、`hashlib`；
5. ARM/Thumb 汇编基础；
6. Ghidra 或 IDA 的内存映射与交叉引用；
7. RTOS 的任务、队列、ISR/HISR 和内存模型；
8. USBPcap/Wireshark 抓取 USB Bulk/CDC 数据；
9. 固件启动链、校验与安全启动；
10. 最后再研究安全刷写和定制固件。

## 12. 文件清单

```text
E:\develop\github\LB15i_flash_20260915_2315.bin
E:\develop\github\LB15i_analysis\
├── LB15i_ROUTER_RESEARCH_REPORT.md
├── at_command_table.csv
├── capture_diag_log19.ps1
├── com4_log19_capture.bin
├── extract_at_table.py
├── extract_lzma_segments.py
├── find_pcrel_xrefs.py
├── oslo_map.py
├── probe_wifi_cmdline.ps1
├── query_debug_at.ps1
├── verify_final_state.ps1
├── xref_strings.py
├── extracted\
│   ├── manifest.json
│   ├── oslo_*.bin
│   ├── grbi_*.bin
│   └── rfbn_*.bin
└── vendor\
    └── capstone ...
```

## 13. 最终判断

这台 LB15i 的 stock 固件没有可通过 SSH/Telnet 获得的 Linux root shell。继续围绕用户名、密码或网页 Telnet 开关尝试，收益很低。

已经找到的正确技术路线是：

```text
COM3 私有 AT
  ├── 设备控制与状态查询
  └── AIC8800 Wi-Fi 工程控制台

COM4 ICAT/DIAG
  ├── 需要 CATStudio 类主机握手
  ├── 需要匹配 DB 才能完整解码
  └── 可通过工具抓包继续恢复协议

离线固件逆向
  ├── TIM/NTIM
  ├── 多段 LZMA
  ├── RTOS ARM Thumb
  ├── AT 注册表
  └── 最终可能实现安全的定制工程接口
```

现阶段最有价值的下一步，是取得可信的 CATStudio 和与当前固件精确匹配的数据库，然后抓取一次完整握手；不是继续尝试打开 22/23 端口。
