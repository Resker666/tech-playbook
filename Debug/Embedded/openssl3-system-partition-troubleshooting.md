# 问题排查总结：OpenSSL 3.x 升级与固定 system 分区超限

> 脱敏公开版草稿  
> 说明：已移除或泛化产品名称、板级标识、内部仓库/分支/提交、内部源码路径、精确分区表、公司/第三方项目标识等信息，仅保留可复用的技术结论和排障方法。

## 1. 核心结论

### 问题现象

某 MIPS32 嵌入式 Linux 设备因安全整改，需要将 OpenSSL 1.1.1 系列升级到 OpenSSL 3.x。

升级过程中连续遇到四类问题：

1. OpenSSL 3 API 兼容问题导致编译失败，例如 deprecated API 被 `-Werror` 提升为错误，以及旧版本中存在的常量已被移除。
2. 仅替换 OpenSSL 动态库不足以完成升级，旧版 curl 等消费者仍依赖 OpenSSL 1.1.1 ABI，以及 SRP / ENGINE 等可选符号。
3. OpenSSL 3 体积增大后，经过 strip、SquashFS、加密、verity 等完整打包流程生成的最终 system 镜像超过固定分区上限。
4. 为提高压缩率，曾尝试增大 SquashFS block size，但设备随后出现 verity / SquashFS 挂载失败并反复重启。

### 最终根因

这是多个独立问题叠加，而不是单一根因：

- **已确认：API / ABI 不兼容。**
  OpenSSL 3 删除了部分旧 API / 常量，并将大量低层 API 标记为 deprecated；旧消费者仍可能引用 `.so.1.1`、ENGINE、SRP 等符号。
- **已确认：最终镜像容量不足。**
  升级后的最终 system 产物超过固定分区限制。
- **高度可信但底层机理尚未完全确认：**
  增大 SquashFS block size 后生成的镜像与当前加密 / verity / 挂载链路存在兼容性问题。恢复原 block size 后问题消失，但未继续定位具体限制位于哪一层。
- **已确认：**
  `/system` 未成功挂载后出现的 DNS、应用、日志等异常属于后续连锁表现，并不是 OpenSSL 业务逻辑本身直接导致。

### 最终解决方案

1. 升级到 OpenSSL 3.x，并针对目标设备进行功能裁剪。
2. 保留设备原有 SquashFS block 参数，不通过改变文件系统格式强行压缩镜像。
3. 使用 `-Os`、section GC、stack protector、RELRO、NOW、noexecstack 等编译 / 链接参数。
4. 根据真实业务依赖裁剪 OpenSSL 功能，同时保留设备实际需要的 TLS、DTLS、RSA、AES、SHA、DH、EC、ECDH / ECDSA、OCSP 等能力。
5. 按依赖顺序重新编译 OpenSSL、curl、wpa_supplicant 等消费者，确保最终产物统一依赖 `libssl.so.3` / `libcrypto.so.3`。
6. 删除业务代码中已经被 OpenSSL 3 移除、且业务并未实际依赖的旧常量分支。
7. 在固件构建流程中加入分区镜像大小硬限制，构建阶段直接阻止超限产物发布。

### 修复验证结果

已完成以下验证：

- OpenSSL 3.x 版本检查通过。
- curl、wpa_supplicant 等消费者均依赖 `.so.3`，不再依赖 `.so.1.1`。
- OpenSSL 动态库 SONAME、RELRO、NOW、不可执行栈等检查通过。
- 最终 system 镜像低于固定分区上限，但剩余空间仍较小。
- `/system` 最终可以正常以 SquashFS 只读方式挂载。
- HTTPS 实测使用 TLS 1.3，证书校验成功。
- 云端请求和文件上传正常。
- 设备完成基础稳定性运行验证，未再次出现因 system 挂载失败导致的重启。

### 当前遗留风险

- system 分区剩余空间较小，后续增加运行文件可能再次触发超限。
- 当前 OpenSSL 裁剪配置是针对单一产品 / 平台验证的，不应未经验证直接复用于其他产品。
- 其他产品如果继续使用旧 curl 或其他旧消费者，仍可能依赖 SRP / ENGINE 等符号。
- 多设备、OTA 升级 / 回滚、异常断电、弱网和更长时间压力测试仍需补充。
- 增大 SquashFS block 后失败的具体底层限制尚未完全确认。
- 排查期间曾观察到网络、P2P 或其他业务异常，但没有证据证明由 OpenSSL 升级直接导致。

### 最值得记住的经验

升级基础加密库不能只替换 `libssl` / `libcrypto`。

必须同时检查：

- 所有消费者的 ABI
- 动态库 `NEEDED`
- 未定义符号
- 静态库
- 编译期 feature detection
- 镜像压缩
- 加密 / verity 元数据
- 分区大小
- 设备端挂载链路

对于固定分区设备，应以**最终签名 / verity 产物大小**为准，而不是仅比较源文件或未签名 SquashFS 大小。

---

## 2. 背景与环境

本次问题环境可概括为：

| 项目 | 信息 |
| --- | --- |
| 设备类型 | 嵌入式 Linux 设备 |
| 架构 | MIPS32 |
| 内核 | Linux 4.4 系列 |
| 工具链 | GCC 5.x 交叉编译工具链 |
| C 运行库 | uClibc |
| 原 OpenSSL | 1.1.1 系列 |
| 目标 OpenSSL | 3.x |
| HTTP 客户端 | curl 8.x |
| Wi-Fi 用户态组件 | wpa_supplicant 2.x |
| system 文件系统 | SquashFS + xz |
| 完整性保护 | dm-crypt + dm-verity |
| system 分区 | 固定大小，只读镜像 |

这里刻意不保留产品型号、板级编号、内部仓库、分支、提交哈希和精确分区布局。

---

## 3. 问题现象

### 3.1 OpenSSL 3 编译兼容错误

OpenSSL 3 头文件下，旧代码可能因为 deprecated API 加上 `-Werror` 而停止编译：

```text
error: 'RSA_new' is deprecated:
Since OpenSSL 3.0 [-Werror=deprecated-declarations]
```

业务代码中还存在 OpenSSL 3 已移除的旧常量：

```text
error: 'RSA_SSLV23_PADDING' undeclared
```

这里需要区分两种情况：

- API 仍存在但被标记 deprecated
- API / 常量已经真正删除

二者的处理策略不同。

### 3.2 system 分区未挂载后的连锁异常

设备异常启动时可能出现：

```text
ping: bad address '<hostname>'
logread: can't find syslogd buffer: No such file or directory
```

同时检查 `/system`：

```sh
mount | grep ' /system '
ls -l /system
```

如果 `/system` 为空或没有挂载，则 DNS、应用、日志服务等后续异常不能直接归因到 TLS / OpenSSL。

应先排查 system 镜像和挂载链路。

### 3.3 verity / SquashFS 失败

修改 SquashFS 参数后，设备出现类似：

```text
Not a valid squashfs filesystem
Failed to get squashfs fs size
Could not get target device size
Verity fail
```

另一次可能表现为：

```text
Could not seek to start of verity metadata block.
Verity fail
```

而旧版本可以正常：

```text
Verity success
Mount system to /system success
```

这类对照说明应优先检查：

- 镜像格式
- 加密布局
- verity metadata
- block size
- 打包工具链

而不是先修改应用代码。

### 3.4 最终镜像超出固定分区

回退到已知兼容的 SquashFS 参数后，完整构建明确报告 system 镜像超过分区上限。

关键经验：

> 判断镜像是否超限，应检查完整打包流程生成的最终产物，而不是仅检查源目录或未签名 SquashFS。

最终镜像大小通常会受到以下因素影响：

```text
ELF strip
  -> SquashFS
  -> block alignment
  -> encryption
  -> verity metadata
  -> signing / packaging
```

### 3.5 与升级同时出现的其他业务异常

排查期间还可能出现网络或 P2P 相关告警。

如果同期存在：

```text
TLS 1.3 handshake success
certificate verify ok
HTTP 200
```

则不能仅凭“时间上同时发生”就把其他网络异常归因于 OpenSSL。

必须寻找独立证据。

---

## 4. 排查思路与过程

| 阶段 | 观察到的证据 | 判断 | 验证方式 | 结果 |
| --- | --- | --- | --- | --- |
| 确认升级范围 | 原系统使用 OpenSSL 1.1.1 | 基础库需要升级 | 检查源码、脚本和二进制 | 确认升级入口 |
| 编译兼容 | deprecated API、删除常量 | OpenSSL 3 API 兼容问题 | 根据编译错误定位调用点 | 仅保留必要源码修改 |
| ABI 检查 | 旧消费者链接 `.so.1.1` | 不能只替换 OpenSSL | `readelf -d`、`nm -u` | 必须重编消费者 |
| 首次设备异常 | `/system` 为空 | 问题可能在挂载层 | `mount`、`dmesg`、`dmsetup` | system 未挂载 |
| 分区容量 | 固定 system 分区 | 新库可能导致镜像超限 | 检查最终镜像字节数 | 确认容量问题 |
| 压缩试验 | 尝试增大 block | 希望提升压缩率 | 修改参数并刷机 | verity / SquashFS 失败 |
| 回退参数 | 旧格式可正常挂载 | 恢复兼容格式 | 使用原 block size | 启动链路恢复 |
| OpenSSL 裁剪 | 默认功能较多 | 从功能集合减少体积 | 扫描实际依赖符号 | 找到可关闭项 |
| 最终容量验证 | 需要计入完整打包开销 | 源文件大小不能代表最终占用 | 正式构建链路 | 最终镜像低于上限 |
| 设备回归 | system 挂载正常 | 升级链路基本可用 | TLS、网络、运行稳定性检查 | 基础验证通过 |

---

## 5. 关键检查命令

### 5.1 system / dm-verity / SquashFS

```sh
cat /proc/mtd
mount | grep ' /system '
df -k /system
du -sk /system
ls -l /dev/dm-*
dmsetup table
dmesg | grep -Ei 'squashfs|verity|mtd|system|mount|flash|error'
```

注意：

```text
df /system 显示 100%
```

对于固定大小、只读 SquashFS 镜像并不一定表示“磁盘空间耗尽”。

`du` 显示的是解压后的逻辑文件大小，不能直接与 flash 分区大小比较。

### 5.2 ABI 和动态库依赖

```sh
readelf -d <libcurl.so> | grep -E 'libssl|libcrypto'
readelf -d <wpa_supplicant> | grep -E 'libssl|libcrypto'

readelf -d <libssl.so.3> <libcrypto.so.3> \
  | grep -E 'SONAME|BIND_NOW|FLAGS_1'

readelf -lW <libssl.so.3> <libcrypto.so.3> \
  | grep -E 'GNU_STACK|GNU_RELRO'
```

查看未定义符号：

```sh
<cross-nm> -D -u <libcurl.so>
<cross-nm> -u <wpa_supplicant>
```

重点关注：

```text
ENGINE_*
SSL_CTX_set_srp_*
```

如果裁剪 OpenSSL 时关闭了这些能力，但旧消费者仍引用这些符号，则运行时或链接阶段仍会失败。

---

## 6. 走过的弯路与踩坑

### 6.1 用错误目标库确认 OpenSSL 补丁版本

**问题：**

只在 `libssl.so.3` 中搜索完整版本字符串，可能得不到结果。

**经验：**

- 完整版本字符串优先检查 `libcrypto.so.3`
- SONAME 使用 `readelf -d`
- 不要用 `strings | grep SONAME` 替代 ELF metadata 检查

---

### 6.2 只替换 OpenSSL，不重编消费者

**为什么容易犯：**

表面上只是从 `libssl/libcrypto` 旧版本升级到新版本。

**实际问题：**

OpenSSL 1.1.1 到 3.x 存在 ABI 变化，旧消费者仍可能：

- 依赖 `.so.1.1`
- 引用 ENGINE
- 引用 SRP
- 使用旧 API

**正确做法：**

先执行：

```sh
readelf -d
nm -u
```

建立消费者依赖图，然后按依赖顺序重新编译。

---

### 6.3 为压制 deprecated warning 扩大第三方代码修改

deprecated warning 与 API 删除不是一回事。

如果只是 warning，被 `-Werror` 放大，应优先考虑：

- 编译配置
- 统一兼容选项
- 最小调用点修改

不要因为升级基础库就大范围改第三方 SDK。

---

### 6.4 通过增大 SquashFS block 强行节省空间

增大 block size 理论上可能提高 xz 压缩率，但文件系统格式参数也是启动链路的一部分。

在嵌入式设备上，消费者可能包括：

```text
boot scripts
dm-crypt
dm-verity
SquashFS reader
vendor tools
recovery / OTA tools
```

因此改变 block size 前必须验证完整链路，而不能只在 PC 上确认 `mksquashfs` 成功。

---

### 6.5 用源码目录文件大小推断设备占用

源码目录中的 ELF 可能没有 strip。

正确容量分析应基于：

```text
正式 strip
  -> 正式 SquashFS
  -> 正式加密
  -> 正式 verity
  -> 最终 image
```

最终判断依据永远是烧写 / 发布使用的最终产物。

---

### 6.6 把 SquashFS `df 100%` 当作空间耗尽

SquashFS 是只读固定镜像，设备侧 `df` 显示 100% 可以是正常现象。

真正需要关心的是：

```text
最终 image size <= flash partition limit
```

---

### 6.7 把时间上同时出现的网络异常归因于 OpenSSL

如果 P2P 报错同时存在：

```text
DNS 正常
TLS 1.3 正常
证书校验正常
HTTP 请求正常
文件上传正常
```

那么就缺乏证据证明 P2P 异常来自 OpenSSL。

排障文档必须严格区分：

- 已确认
- 基于现象的推测
- 尚未验证

---

### 6.8 在脏工作区准备安全升级提交

基础库升级经常会同时涉及：

- 二进制
- key
- 版本文件
- 调试脚本
- patch
- 日志
- 临时产物

应从干净分支开始，并按路径暂存。

避免：

```sh
git add .
```

---

## 7. 根因分析

### 7.1 API / ABI 层

升级前：

```text
应用
  -> libcurl
      -> libssl.so.1.1
      -> libcrypto.so.1.1
```

升级后：

```text
应用
  -> 新 libcurl
      -> libssl.so.3
      -> libcrypto.so.3

wpa_supplicant
  -> libssl.so.3
  -> libcrypto.so.3
```

不能保留旧消费者，再单独替换底层 TLS 库。

---

### 7.2 应用源码层

OpenSSL 3 删除了一些历史 API / 常量。

处理原则：

1. 先确认调用是否真实存在。
2. 判断业务是否实际依赖该能力。
3. 如果只是枚举 / 分支残留，应最小化删除。
4. 如果业务真实依赖，则应迁移到 OpenSSL 3 推荐 API，而不是简单删除。

---

### 7.3 镜像容量层

固定 flash 分区设备的镜像大小不能只看：

```text
libssl.so
libcrypto.so
```

真正限制的是：

```text
所有运行文件
+ strip 后大小
+ SquashFS
+ 对齐
+ 加密
+ verity metadata
+ 打包开销
```

因此构建系统必须对**最终镜像**执行硬限制检查。

---

### 7.4 启动挂载层

典型启动路径：

```text
flash system partition
  -> dm-crypt
  -> dm-verity
  -> SquashFS
  -> mount /system
  -> start application services
```

如果前面的 dm-verity / SquashFS 失败：

```text
/system 为空
  -> 应用不存在
  -> 服务未启动
  -> DNS / 日志 / 业务功能异常
```

因此不能从最末端的业务错误倒推出 TLS 库故障。

---

## 8. 最终解决方案

### 8.1 OpenSSL 3.x 裁剪构建

推荐的优化 / hardening 思路：

```sh
CFLAGS="-Os -fstack-protector-strong -ffunction-sections -fdata-sections"

LDFLAGS="-fstack-protector-strong \
  -Wl,--gc-sections \
  -Wl,-z,noexecstack \
  -Wl,-z,relro \
  -Wl,-z,now"
```

可选功能应根据实际依赖裁剪，而不是照搬某个产品的配置。

例如可能评估：

```text
ENGINE
SRP
legacy algorithms
unused protocols
test tools
optional modules
```

但是裁剪前必须检查消费者的未定义符号和源码 feature detection。

---

### 8.2 依赖重新编译顺序

推荐：

```text
OpenSSL
  -> curl
  -> wpa_supplicant
  -> application / firmware
```

每一步都确认：

```sh
readelf -d
nm -u
```

---

### 8.3 保留已验证的 SquashFS 参数

当已有固件使用某组稳定参数时，不应为了少量空间收益直接改变格式参数。

优先通过：

- `-Os`
- dead code elimination
- `--gc-sections`
- OpenSSL feature trimming
- 删除真正未使用资源

来降低镜像大小。

---

### 8.4 加入分区大小门禁

构建系统应维护每个固定分区的容量限制。

伪代码：

```sh
actual_size=$(stat -c%s "$image")

if [ "$actual_size" -gt "$partition_limit" ]; then
    echo "Error: image exceeds partition limit"
    exit 1
fi
```

检查应该发生在：

> 最终格式、最终加密、最终 verity / 签名之后。

---

## 9. 验证方法

### 主机侧

- OpenSSL 编译通过
- curl 重编通过
- wpa_supplicant 重编通过
- `git diff --check`
- SONAME 检查
- `NEEDED` 检查
- undefined symbol 检查
- RELRO / NOW / GNU_STACK 检查
- 最终镜像容量检查

### 设备侧

```sh
mount | grep ' /system '
ls -l /system/lib/libssl.so*
ls -l /system/lib/libcrypto.so*
```

功能验证：

- 正常启动
- `/system` 正常挂载
- DNS
- HTTPS
- TLS 1.3
- 证书校验
- 云端请求
- 文件上传
- Wi-Fi
- 重启稳定性

待进一步验证：

- 多设备
- OTA 升级
- OTA 回滚
- back / fallback 分区
- 多次冷启动
- 弱网
- 路由器重启
- 长时间运行
- 内存趋势
- 安全扫描 / SBOM

---

## 10. 可复用经验

1. **升级 OpenSSL 前先画依赖图。**
2. **先查 ABI，再复制文件。**
3. **头文件里有声明，不代表该功能最终一定被编译进去。**
4. **消费者的可选功能也可能形成真实链接依赖。**
5. **OpenSSL 完整版本优先从 `libcrypto` 确认，SONAME 用 `readelf`。**
6. **固定分区容量只看最终发布产物。**
7. **SquashFS `df 100%` 不等于普通文件系统空间耗尽。**
8. **文件系统格式参数属于启动协议的一部分。**
9. **构建阶段必须建立分区大小门禁。**
10. **基础库升级应保持干净提交边界。**
11. **针对单一产品裁剪出的配置不能直接当作全平台通用配置。**
12. **运行日志必须寻找反证，不能因为时间相关性就认定因果关系。**

---

## 11. 后续行动清单

- [ ] 在干净 CI / release 环境完成一次全量构建并归档最终镜像大小。
- [ ] 验证旧版本到新版本的 OTA 升级。
- [ ] 验证 OTA 失败回滚和 fallback 分区。
- [ ] 执行多次断电冷启动。
- [ ] 完成弱网、断网重连、路由器重启回归。
- [ ] 扩展多设备与更长时间稳定性测试。
- [ ] 使用安全扫描器确认旧 OpenSSL 不再存在。
- [ ] 对其他产品分别检查 curl / wpa 等消费者的 ENGINE / SRP 等依赖。
- [ ] 将 OpenSSL 裁剪参数做成明确的产品 profile。
- [ ] 持续监控 system 分区余量。

---

## 60 秒口头汇报版本

这次问题发生在嵌入式设备从 OpenSSL 1.1.1 升级到 OpenSSL 3.x 的过程中。升级并不是简单替换两个动态库：OpenSSL 3 存在 API / ABI 变化，旧 curl 等消费者仍可能依赖旧 SONAME、ENGINE 和 SRP，因此必须同步重编消费者。同时，新版库体积增大，使最终 system 镜像超过固定 flash 分区。我们曾尝试通过增大 SquashFS block 提高压缩率，但设备出现 verity / SquashFS 挂载失败，所以最终恢复原有文件系统参数，通过 OpenSSL 功能裁剪、`-Os` 和 section GC 控制体积，并在构建流程中增加最终镜像大小门禁。最终 `/system` 可以正常挂载，TLS 1.3、证书校验、网络请求和上传功能通过验证。最重要的经验是：嵌入式基础库升级必须同时关注 API、ABI、消费者依赖、最终镜像容量和完整启动挂载链路。
