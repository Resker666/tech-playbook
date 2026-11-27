# CPU 架构与软件版本选择（x86 / x64 / ARM64）

## 1. 常见架构

| 下载标识 | 常见别名 | 说明 |
| --- | --- | --- |
| x86 (32-bit) | i386、i686、x32（部分软件的俗称） | 32 位 x86 |
| x64 (64-bit) | x86_64、AMD64 | Intel 和 AMD 主流 64 位 PC |
| ARM (32-bit) | armv7l、armhf（特定 ABI） | 常见于较早的嵌入式设备 |
| ARM64 (64-bit) | AArch64、aarch64 | Apple Silicon、部分骁龙 Windows PC、64 位 ARM 嵌入式设备 |

AMD64 是架构名称，不代表 CPU 必须是 AMD 品牌。ARM64 与 x64 虽然都是 64 位，但指令集不同，不能直接混用原生二进制。严格来说，x32 也可指 Linux 上一种特殊的 x86-64 ABI，不宜作为正式架构名。

## 2. Windows：如何选择安装包

### 图形界面

按 Win + I → 系统 → 关于（系统信息）→ 设备规格 → 系统类型。

- 64 位操作系统，基于 x64 的处理器：选择 x64。
- 64 位操作系统，基于 ARM 的处理器：优先选择 ARM64。
- 32 位操作系统：选择适用于该系统的 32 位程序。

### PowerShell

```powershell
$env:PROCESSOR_ARCHITECTURE
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
```

第一条反映当前进程环境，可能受 WOW64 或模拟运行影响；后两条分别查看操作系统与进程架构（需要支持 RuntimeInformation 的 .NET/PowerShell 环境）。也可以运行 `msinfo32` 查看系统类型。

| 常见输出 | 推荐下载 |
| --- | --- |
| AMD64 / X64 | x64 |
| x86 / X86 | x86 |
| ARM64 / Arm64 | ARM64 |

64 位 x86 Windows 通常也能运行 32 位 x86 应用，但驱动等内核组件有额外限制。Windows 11 on ARM 支持许多 x86/x64 应用的模拟运行，但优先选原生 ARM64 版本。

### 实例：PotPlayer

官网：https://potplayer.tv/

官网提供 x86 (32bit)、x64 (64bit)、arm64 三种 Windows 安装包。普通 Intel/AMD 64 位 Windows PC 选择 x64；具体以本机系统类型为准。

## 3. Linux：查询系统与程序架构

```sh
uname -m
getconf LONG_BIT
file /bin/sh
file -L /bin/sh
readelf -h ./app
```

- `uname -m`：查看内核报告的机器架构，例如 x86_64、aarch64、armv7l、mips。
- `getconf LONG_BIT`：查看当前用户空间环境中 long 类型的位数；不等同于物理 CPU 位数。
- `file -L`：跟随软链接，查看实际 ELF 文件的架构、位数等。
- `readelf -h`：重点看 Class（ELF32/ELF64）、Machine（指令集）和 Data（字节序）。
- 精简 BusyBox 固件可能缺少 file、readelf 或 getconf，可把目标文件复制到开发机分析。

## 4. macOS

```sh
uname -m
arch
sysctl -n hw.optional.arm64
file ./app
```

Apple Silicon 原生终端通常显示 arm64，Intel Mac 通常显示 x86_64（arch 在 Intel 环境也可能显示 i386）。Rosetta 下的进程可能显示 x86_64，因此不能仅凭当前进程的架构判断硬件。hw.optional.arm64 在 Apple Silicon 上通常为 1。Universal 应用可同时包含两种架构的二进制。

## 5. 嵌入式开发注意事项

CPU 指令集、内核架构、用户空间 ABI、应用二进制架构是不同层次。选择 SDK、交叉编译器或第三方库时，不只看 32/64 位，还需检查：

- 目标指令集（ARM、MIPS、RISC-V 等）及其具体版本；
- 大端/小端、ABI（例如 ARM hard-float/soft-float）、动态链接器和 libc 版本；
- 编译器目标和产物是否与设备匹配。

```sh
# 在开发机执行，编译器名称按实际工具链替换
aarch64-linux-gnu-gcc -dumpmachine
file ./app
readelf -h ./app
readelf -l ./app
```

遇到 Exec format error 时，优先检查二进制格式、架构和 ABI 是否匹配；若文件存在却提示 No such file or directory，还应检查 ELF 解释器（动态链接器）是否存在。

## 6. 速查原则

先确认目标系统和运行环境的架构，再选择匹配的原生安装包或编译产物；不能仅凭“64 位”判断兼容性。

记录日期：2026-11-27。命令为通用查询示例，未在具体设备上逐条实测。
