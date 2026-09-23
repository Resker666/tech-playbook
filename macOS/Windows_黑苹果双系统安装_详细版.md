# Windows 笔记本安装 macOS 黑苹果双系统技术沉淀

> 项目类型：Intel Windows 笔记本 + OpenCore + macOS 双系统\
> 目标：保留 Windows，通过 OpenCore 统一管理 macOS / Windows 启动。

------------------------------------------------------------------------

# 1. 项目背景

本次目标是在已有 Windows 笔记本上安装 macOS 黑苹果系统，并实现：

-   BIOS 开机进入 OpenCore
-   OpenCore 菜单选择 macOS
-   OpenCore 菜单选择 Windows
-   避免 Windows Boot Manager 抢占启动
-   后续方便维护 EFI

OpenCore 是黑苹果环境中常用的 UEFI 引导方案，用于向 macOS 注入
SMBIOS、ACPI、Kext 等配置。官方维护项目为
Acidanthera/OpenCorePkg，配置参考主要来自 Dortania OpenCore Install
Guide。

参考： - OpenCorePkg: https://github.com/acidanthera/OpenCorePkg -
OpenCore Install Guide:
https://github.com/dortania/OpenCore-Install-Guide

------------------------------------------------------------------------

# 2. 硬件环境

## 笔记本

-   CPU: Intel Core i5-10210U

-   GPU: Intel UHD Graphics

-   内存: 16GB

-   无线: Intel Wireless-AC 9560

-   启动方式: UEFI + GPT

------------------------------------------------------------------------

# 3. 使用的软件与 Github 项目

## 3.1 OpenCore

用途：

-   UEFI Bootloader
-   引导 macOS
-   管理 Windows/macOS 双启动

项目：

https://github.com/acidanthera/OpenCorePkg

------------------------------------------------------------------------

## 3.2 Dortania OpenCore Install Guide

用途：

-   查找硬件对应配置
-   配置 config.plist
-   学习 ACPI/Kext 设置

项目：

https://github.com/dortania/OpenCore-Install-Guide

------------------------------------------------------------------------

## 3.3 ProperTree

用途：

-   修改 config.plist
-   Clean Snapshot
-   管理 OpenCore 配置

项目：

https://github.com/corpnewt/ProperTree

关键操作：

Windows:

    ProperTree.bat

macOS:

    ProperTree.command

修改 config.plist 后需要检查：

-   ACPI
-   Drivers
-   Kexts
-   Tools

------------------------------------------------------------------------

## 3.4 GenSMBIOS

用途：

生成 SMBIOS：

-   SystemProductName
-   SerialNumber
-   MLB
-   UUID

项目：

https://github.com/corpnewt/GenSMBIOS

------------------------------------------------------------------------

# 4. EFI 目录设计

最终 EFI：

    EFI
    |
    ├── BOOT
    │   └── BOOTx64.efi
    │
    ├── OC
    │   |
    │   ├── OpenCore.efi
    │   ├── config.plist
    │   ├── ACPI
    │   ├── Drivers
    │   ├── Kexts
    │   └── Tools
    │
    ├── Microsoft
    │   └── Boot
    │       └── bootmgfw.efi
    │
    └── WindowsEFI
        └── Boot
            └── bootmgfw.efi

------------------------------------------------------------------------

# 5. 安装过程

## 5.1 准备 EFI

准备：

-   OpenCore
-   ACPI
-   Kext
-   Drivers
-   config.plist

配置：

    EFI/OC/config.plist

使用 ProperTree 修改。

------------------------------------------------------------------------

## 5.2 macOS 安装

流程：

1.  创建 macOS 安装介质
2.  OpenCore 引导
3.  安装 macOS
4.  调整 EFI

------------------------------------------------------------------------

# 6. 遇到的问题记录

# 问题1：BIOS 无法稳定进入 OpenCore

现象：

-   BIOS 中 HDD 没有明显 OpenCore 子项
-   重启后经常直接进入 Windows

排查：

比较 EFI 文件 MD5：

``` bash
md5 /Volumes/OPENCORE/EFI/BOOT/BOOTx64.efi

md5 /Volumes/EFI/EFI/BOOT/BOOTx64.efi
```

结果：

MD5 一致。

说明：

-   BOOTx64.efi 文件没有问题
-   OpenCore 文件没有损坏

问题定位：

Windows EFI 启动项优先级更高。

------------------------------------------------------------------------

# 问题2：Windows 抢占 BIOS 启动

原因：

Windows 默认入口：

    EFI/Microsoft/Boot/bootmgfw.efi

BIOS 会优先寻找 Windows Boot Manager。

导致：

    BIOS
     |
     +-- Windows Boot Manager
           |
           Windows

绕过 OpenCore。

------------------------------------------------------------------------

# 问题3：复制 Windows EFI

为了让 OpenCore 管理 Windows：

创建：

    EFI/WindowsEFI/Boot/bootmgfw.efi

目的：

分离 Windows 原始入口。

原结构：

    EFI/Microsoft/Boot/bootmgfw.efi

修改后：

    EFI
    |
    ├── Microsoft
    |
    └── WindowsEFI
        └── Boot
            └── bootmgfw.efi

------------------------------------------------------------------------

# 问题4：BlessOverride 引导 Windows

OpenCore:

    Misc
     |
     └── BlessOverride

添加：

    \EFI\WindowsEFI\Boot\bootmgfw.efi

效果：

OpenCore 可以找到 WindowsEFI。

验证：

第二个 Windows 入口可以正常启动。

------------------------------------------------------------------------

# 问题5：OpenCore 出现多个 Windows

原因：

同时存在：

1.  自动扫描：

```{=html}
<!-- -->
```
    EFI/Microsoft/Boot/bootmgfw.efi

2.  BlessOverride:

```{=html}
<!-- -->
```
    EFI/WindowsEFI/Boot/bootmgfw.efi

3.  手动 Entries:

```{=html}
<!-- -->
```
    Misc/Entries

导致：

    Windows
    Windows
    Windows

------------------------------------------------------------------------

# 问题6：手动 Entries 失败

尝试：

    Misc
     |
     └── Entries
          Path=\WindowsEFI\Boot\bootmgfw.efi

启动：

    OCB: LoadImage failed - Not Found

原因：

OpenCore Entry 对设备路径解析更加严格。

最终恢复：

使用 BlessOverride。

------------------------------------------------------------------------

# 7. 最终稳定方案

当前稳定启动链：

    BIOS
     |
     v
    EFI/BOOT/BOOTx64.efi
     |
     v
    OpenCore
     |
     +---- macOS
     |
     +---- WindowsEFI/Boot/bootmgfw.efi

已经实现：

✅ BIOS 不直接进入 Windows\
✅ OpenCore 可以启动 macOS\
✅ OpenCore 可以启动 Windows

------------------------------------------------------------------------

# 8. 后续优化方向

## 8.1 隐藏错误 Windows

当前：

    Windows (错误入口)
    Windows (正确入口)

后续使用：

-   ScanPolicy
-   Hide Entries

进行优化。

------------------------------------------------------------------------

## 8.2 修改 Timeout

位置：

    Misc
     |
     └── Boot
          └── Timeout

例如：

    Timeout=5

减少等待。

------------------------------------------------------------------------

# 9. 经验总结

1.  黑苹果启动问题优先检查 EFI 结构。
2.  修改 EFI 前必须备份。
3.  Windows EFI 和 OpenCore 容易冲突。
4.  不要同时使用多个 Windows 引导入口。
5.  先保证稳定启动，再优化菜单。
6.  每次修改 config.plist 后保留可恢复版本。

------------------------------------------------------------------------

# 10. 本次排障核心结论

真正的问题不是：

-   OpenCore 文件损坏
-   BOOTx64.efi 错误
-   config.plist 无效

而是：

Windows 默认 EFI：

    EFI/Microsoft/Boot/bootmgfw.efi

抢占 BIOS。

最终通过：

    EFI/WindowsEFI/Boot/bootmgfw.efi

    +

    OpenCore BlessOverride

解决。
