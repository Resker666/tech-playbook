# ELF 文件格式与嵌入式 Linux 排查速查

> ELF 是一种文件格式，不等于“所有二进制文件”。本文以 Linux / 嵌入式 Linux 为场景，记录 ELF 的基本结构、分析命令和常见排障思路。

## 1. ELF 是什么？

ELF（Executable and Linkable Format）是一种可执行文件与链接目标的标准格式。Linux 系统中的 ELF 文件常见于：

| 类型 | 常见示例 | 说明 |
| --- | --- | --- |
| 可执行程序 | `app`、`iCamera` | 通常由内核及动态加载器配合装载执行 |
| 共享库 | `libxxx.so` | 可由动态链接器加载，也可能由程序通过 `dlopen` 加载 |
| 可重定位目标文件 | `xxx.o` | 编译后、最终链接前的目标文件 |
| Core Dump | `core`、`core.*` | 记录进程崩溃时状态的文件（系统配置允许时） |

注意：Shell 脚本、PNG 图片、纯数据 `.bin` 和固件镜像不一定是 ELF；`.a` 静态库通常是 `ar` 归档容器，其成员 `.o` 可以是 ELF。

在设备或编译机上先确认文件类型：

```bash
file iCamera
```

可能看到（仅为示例，具体以实际设备输出为准）：

```text
iCamera: ELF 32-bit LSB executable, MIPS, ...
```

- `ELF 32-bit`：32 位 ELF 文件格式，不代表一定兼容当前 CPU / 系统。
- `LSB`：Little-Endian（小端字节序）；相对的是 `MSB`（大端）。
- `executable`：可执行目标文件；现代 PIE 可执行程序也可能显示为 `shared object`。
- `MIPS`：目标架构，和 x86、ARM、AArch64 并不通用。

## 2. ELF 的整体结构

ELF 文件通常包含以下结构（并非每个 ELF 都有完整的两张表）：

```text
+-----------------------------+
| ELF Header                  |  文件身份、架构、入口地址、表位置
+-----------------------------+
| Program Header Table        |  描述运行时的 Segment（段）
+-----------------------------+
| Sections / Segment contents |  代码、数据、符号等内容
+-----------------------------+
| Section Header Table        |  描述各个 Section（节）
+-----------------------------+
```

### 2.1 ELF Header

文件开头的 ELF Header 用来标识文件及其基础属性。前 4 字节魔数通常为 `7f 45 4c 46`（`0x7F` + `ELF`）。

```bash
readelf -h ./iCamera
```

重点关注：

| 字段 | 用途 |
| --- | --- |
| `Class` | `ELF32` / `ELF64` |
| `Data` | 小端 / 大端字节序 |
| `Type` | 目标文件类型 |
| `Machine` | 目标 CPU 架构 |
| `Entry point address` | 程序入口虚拟地址（对可执行程序有意义） |
| `Flags` | 架构特定信息，例如部分 MIPS ABI 标记 |

常见 `Type`：`REL`（可重定位文件）、`EXEC`（传统可执行文件）、`DYN`（共享对象或 PIE 可执行程序）、`CORE`（Core Dump）。**不能仅凭 `DYN` 断定它是 `.so`**。

### 2.2 Program Header（运行时视角）

```bash
readelf -W -l ./iCamera
```

Program Header 描述装载时如何把文件映射到内存。重点类型：

- `LOAD`：需要装载的内存区域，常带有 `R` / `W` / `E` 权限。
- `INTERP`：动态加载器路径（若存在），例如某些系统中的 `/lib/ld-linux*.so.*`；嵌入式环境也可能使用 musl / uClibc 对应加载器。
- `DYNAMIC`：动态链接相关信息。
- `GNU_STACK`：栈权限相关标记；可辅助检查是否要求可执行栈。
- `GNU_RELRO`：可辅助观察 RELRO 相关内存布局。

**Segment 是装载运行视角；Section 是编译/链接分析视角**。一个 Segment 可以包含多个 Section。

### 2.3 Section Header（链接与分析视角）

```bash
readelf -W -S ./iCamera
```

常见 Section：

| Section | 作用 |
| --- | --- |
| `.text` | 机器指令代码 |
| `.rodata` | 只读常量 |
| `.data` | 已初始化的可写数据 |
| `.bss` | 未初始化或零初始化数据；通常不在文件中存放等量的零字节 |
| `.dynsym` | 动态链接所需的符号表（如存在） |
| `.symtab` | 较完整的符号表，strip 后可能被移除 |
| `.dynamic` | 动态链接信息 |
| `.debug_*` | DWARF 等调试信息，正式固件通常可能剥离 |

说明：某些经过特殊处理的 ELF 可能不包含 Section Header Table，不能仅凭缺失 Section Header 判断文件无效。

## 3. 常用工具与命令

以下命令在 Linux 主机上执行；嵌入式设备上可能只有 BusyBox `file` 的简化实现，或根本没有 `readelf` / `objdump`。可先把文件拷贝到开发机分析。

```bash
# 快速识别文件格式、位数、架构
file ./iCamera

# ELF 基础信息：类型、大小端、架构、入口
readelf -h ./iCamera

# 装载段与动态加载器
readelf -W -l ./iCamera

# Section 列表
readelf -W -S ./iCamera

# 动态链接信息与直接声明的 NEEDED 依赖
readelf -d ./iCamera
readelf -d ./iCamera | grep NEEDED

# 符号与动态符号
readelf -s ./iCamera
readelf --dyn-syms ./iCamera
nm -D ./libxxx.so

# 反汇编；需要 objdump 支持目标架构
objdump -d ./iCamera

# 查看文件各段大小（可用时）
size ./iCamera
```

分析 MIPS / ARM 交叉编译产物时，可能需要对应工具链，例如 `mips-linux-gnu-objdump`、`arm-linux-gnueabihf-readelf`。**实际工具前缀取决于 SDK / 交叉工具链**。`readelf` 通常可跨架构读取 ELF 元数据，但反汇编需要具备相应架构支持。

### 3.1 检查动态加载器与依赖

```bash
# 是否指定了 ELF interpreter；部分静态链接程序没有
readelf -W -l ./iCamera | grep -A1 INTERP

# 直接依赖哪些共享库
readelf -d ./iCamera | grep NEEDED

# 有些链接器会记录运行时查找路径
readelf -d ./iCamera | grep -E "RPATH|RUNPATH"
```

`NEEDED` 只列出文件自身声明的直接依赖，并不等于已经找到这些库。`ldd` 可以在相应运行环境中查看依赖解析结果，但**不要对来源不可信的可执行文件使用 `ldd`**：某些实现/情况可能执行代码。分析未知文件优先使用 `readelf -d` 或 `objdump -p`。

### 3.2 静态链接与动态链接

- **静态链接**：构建时把所需库代码链接进产物；通常没有用于动态库装载的 `PT_INTERP` / `DT_NEEDED`。
- **动态链接**：运行时由动态加载器解析和装载共享库，常见 `.so` / `NEEDED` 条目。
- **PIE**：位置无关可执行文件，ELF 类型常为 `DYN`；它不是普通共享库，不能单凭 `Type` 区分。

## 4. 嵌入式 Linux 常见报错排查

### 4.1 `Exec format error`（无法执行该文件格式）

优先检查文件类型、目标架构、位数、大小端和 ABI 是否与设备匹配：

```bash
file ./app
readelf -h ./app
uname -m                 # 在目标设备上执行
```

例如编译出 ARM / x86 程序却放到 MIPS 设备，或者 64 位程序运行在不支持相应 ABI 的系统中，都可能失败。`uname -m` 只是第一步，仍需核对具体 SoC 指令集、ABI 和系统支持。

### 4.2 文件明明存在，却显示 `No such file or directory`

对于动态链接 ELF，常见原因之一是 **ELF 指定的动态加载器路径不存在**，不是程序文件本身丢失。

```bash
ls -l ./app
readelf -W -l ./app | grep -A1 INTERP
```

然后到目标系统检查该解释器路径是否存在、架构/ABI 是否匹配。其他情况（如脚本解释器路径错误）也会导致类似现象；不要直接断言是动态库问题。

### 4.3 `error while loading shared libraries` / `library not found`

```bash
readelf -d ./app | grep NEEDED
readelf -d ./app | grep -E "RPATH|RUNPATH"
ls -l /lib /usr/lib
```

确认：目标文件系统是否打包了依赖 `.so`、软链接是否正确、所用 libc 与 ABI 是否一致，以及实际动态库搜索路径是否覆盖了安装位置。不要简单地从 PC 复制一份同名 `.so` 到设备。

### 4.4 `Illegal instruction`（非法指令）

先核对实际 CPU 支持的指令集、编译器 `-march` / `-mips*` 等选项和目标工具链配置。**同为 MIPS 或 ARM，并不保证指令集扩展与 ABI 完全兼容**。

### 4.5 崩溃产生 Core Dump

```bash
file ./core
readelf -h ./core
```

确认 Core 的架构及关联程序后，再用匹配架构的 GDB、未剥离符号文件及必要的共享库定位崩溃。Core 可能包含密码、Token、密钥、内存中的敏感数据；**不要将真实 Core、内部 ELF、符号文件或设备日志直接提交到公开仓库**。

## 5. ELF 与二进制安全加固（快速检查）

```bash
# 检查 GNU_STACK 的权限标记；E 可能表示要求可执行栈
readelf -W -l ./app | grep GNU_STACK

# 检查是否存在 RELRO Segment
readelf -W -l ./app | grep GNU_RELRO

# 检查动态标志中是否包含 BIND_NOW / NOW
readelf -d ./app | grep -E "BIND_NOW|FLAGS.*NOW"
```

这些输出是**检查线索**，不是完整的安全证明：是否启用 PIE、NX、RELRO、Stack Canary 以及实际生效情况，还应结合编译/链接参数、目标系统和运行时验证。`Type: DYN` 本身也不能证明 PIE 或其他加固已经正确生效。

## 6. 推荐排查顺序

遇到“设备上的程序无法运行”时，建议按以下顺序：

1. `file`：确认是不是 ELF，以及 CPU 架构、32/64 位和大小端。
2. `readelf -h`：进一步核对 `Machine`、`Type`、ABI 标志。
3. `readelf -l`：确认装载信息与 `INTERP` 动态加载器路径。
4. `readelf -d`：确认 `NEEDED` 和 `RPATH` / `RUNPATH`。
5. 在目标设备核对库文件、文件权限、挂载选项和系统 ABI。
6. 如果程序已经启动但崩溃，再结合日志、GDB、Core 和符号信息排查。

## 参考资料

- [Linux man-pages: elf(5)](https://man7.org/linux/man-pages/man5/elf.5.html)
- [GNU Binutils: readelf](https://sourceware.org/binutils/docs/binutils/readelf.html)
- [GNU Binutils: objdump](https://sourceware.org/binutils/docs/binutils/objdump.html)
- [Linux man-pages: ldd(1)](https://man7.org/linux/man-pages/man1/ldd.1.html)

---

> 适用场景：嵌入式 Linux / 固件构建 / 交叉编译 / 动态库缺失 / ELF 安全配置排查。文中的 `iCamera` 和路径仅用于命令演示，不代表任何特定设备的真实构建信息。
