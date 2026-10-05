# 查看 Windows 版本

在排查系统兼容性、驱动、软件安装或开发环境问题时，经常需要先确认 Windows 的版本和 Build 号。

## 方法 1：使用 `winver`

在 **CMD**、PowerShell 或“运行”窗口中输入：

```cmd
winver
```

会弹出“关于 Windows”窗口，可查看：

- Windows 版本
- 功能版本
- OS Build（内部版本）

适合快速确认当前系统版本。

## 方法 2：使用 `ver`

在 **Windows 命令提示符（CMD）** 中输入：

```cmd
ver
```

示例输出：

```text
Microsoft Windows [版本 10.0.xxxxx.xxxx]
```

该命令适合快速查看 Windows 内核版本和 Build 号。

## 方法 3：使用 `systeminfo`

如果需要更完整的系统信息，可以在 CMD 中输入：

```cmd
systeminfo
```

其中重点关注：

- OS 名称
- OS 版本
- 系统类型
- 处理器
- BIOS 版本
- 初始安装日期

只查看 Windows 名称和版本：

```cmd
systeminfo | findstr /B /C:"OS 名称" /C:"OS 版本"
```

> 在英文版 Windows 中，对应字段通常为 `OS Name` 和 `OS Version`。

## 快速选择

| 命令 | 用途 |
| --- | --- |
| `winver` | 最直观，查看 Windows 版本与 Build |
| `ver` | 最简洁，只查看版本号 |
| `systeminfo` | 查看完整系统与硬件基础信息 |
