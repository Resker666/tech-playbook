# Windows 开机自动弹出 `amdafdapp.exe` 窗口的排查与解决

## 问题现象

Windows 开机后会自动弹出一个黑色 Terminal / 命令行窗口。

窗口对应的程序路径位于：

```text
C:\Windows\System32\DriverStore\FileRepository\
amdacpafdcomp.inf_amd64_xxx\
amdafdapp.exe
```

关闭窗口后仍可能再次出现，影响正常使用。

---

## 初步判断

从程序路径可以看出，`amdafdapp.exe` 位于 Windows DriverStore 中：

```text
C:\Windows\System32\DriverStore\FileRepository\
```

程序名：

```text
amdafdapp.exe
```

结合路径和文件名，初步判断它与 AMD 驱动组件有关。

> 不建议直接删除 DriverStore 中的文件。  
> DriverStore 由 Windows 管理，直接删除驱动文件可能导致驱动异常。

---

## 排查过程

### 1. 检查任务计划程序

按：

```text
Win + R
```

输入：

```text
taskschd.msc
```

打开“任务计划程序”。

在任务计划程序库中发现多个 AMD 相关任务：

```text
AMD Install Manager - Check For Updates
AMDInstallLauncher
AMDRyzenMasterSDKTask
AMDScoSupportTypeUpdate
```

其中重点怀疑以下几个任务与 AMD 驱动更新 / 启动有关：

```text
AMD Install Manager - Check For Updates
AMDInstallLauncher
AMDScoSupportTypeUpdate
```

---

### 2. 禁用可疑 AMD 任务

依次禁用：

```text
AMD Install Manager - Check For Updates
AMDInstallLauncher
AMDScoSupportTypeUpdate
```

保留：

```text
AMDRyzenMasterSDKTask
```

没有继续修改其他无关任务。

---

### 3. 重启验证

禁用上述任务后重启 Windows。

重启后：

- 不再自动弹出 Terminal / 命令行窗口
- `amdafdapp.exe` 不再异常自动启动
- 系统正常使用
- 问题未再次复现

由此确认，本次问题与 AMD 相关计划任务的自动触发有关。

---

## Root Cause

问题根因是 **AMD 安装 / 更新相关计划任务在系统启动或特定触发条件下启动 AMD 驱动组件，进而导致 `amdafdapp.exe` 以可见命令行窗口的形式运行**。

本次禁用以下任务后问题消失：

```text
AMD Install Manager - Check For Updates
AMDInstallLauncher
AMDScoSupportTypeUpdate
```

---

## Solution

打开：

```text
Win + R
```

输入：

```text
taskschd.msc
```

进入：

```text
任务计划程序库
```

找到以下 AMD 相关任务：

```text
AMD Install Manager - Check For Updates
AMDInstallLauncher
AMDScoSupportTypeUpdate
```

右键选择：

```text
禁用
```

然后重启电脑验证。

---

## 为什么不直接删除 `amdafdapp.exe`

`amdafdapp.exe` 位于：

```text
C:\Windows\System32\DriverStore\FileRepository\
```

这是 Windows 驱动仓库。

直接删除其中的文件可能导致：

- AMD 驱动异常
- 音频相关功能异常
- Windows Update / 驱动更新失败
- 后续驱动安装或卸载异常

因此正确的处理思路应该是：

```text
发现异常进程
    ↓
确认程序路径
    ↓
确认程序所属组件
    ↓
检查启动来源
    ↓
禁用或修复真正的触发源
```

而不是直接删除程序文件。

---

## 后续排查方法

如果禁用任务后问题仍然存在，可以继续追踪 `amdafdapp.exe` 的父进程。

### 查询进程和父进程

以管理员身份打开 PowerShell：

```powershell
$p = Get-CimInstance Win32_Process -Filter "Name='amdafdapp.exe'"

$p | Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine

$p | ForEach-Object {
    Get-CimInstance Win32_Process -Filter "ProcessId=$($_.ParentProcessId)" |
    Select-Object Name, ProcessId, ParentProcessId, ExecutablePath, CommandLine
}
```

重点关注：

```text
ProcessId
ParentProcessId
ExecutablePath
CommandLine
```

可以通过父进程判断启动来源。

例如：

```text
services.exe
    ↓
amdafdapp.exe
```

说明可能由 Windows Service 启动。

如果是：

```text
taskhostw.exe
    ↓
amdafdapp.exe
```

则应继续排查计划任务。

---

### 查询 AMD 相关启动项

```powershell
Get-CimInstance Win32_StartupCommand |
Where-Object {
    $_.Command -match "amd|afd|amdacp"
} |
Select-Object Name, Command, Location, User
```

---

### 查询 AMD 相关服务

```powershell
Get-CimInstance Win32_Service |
Where-Object {
    $_.Name -match "amd|afd" -or
    $_.PathName -match "amd|afd|amdacp"
} |
Select-Object Name, DisplayName, State, StartMode, PathName
```

---

### 全局搜索相关计划任务

任务计划程序 GUI 中看到的顶层任务并不是全部任务，因此可以使用 PowerShell 全局搜索：

```powershell
Get-ScheduledTask | ForEach-Object {
    $task = $_

    foreach ($action in $task.Actions) {
        $cmd = "$($action.Execute) $($action.Arguments)"

        if ($cmd -match "amdafdapp|amdacpafdcomp") {
            [PSCustomObject]@{
                TaskName  = $task.TaskName
                TaskPath  = $task.TaskPath
                Execute   = $action.Execute
                Arguments = $action.Arguments
            }
        }
    }
} | Format-List
```

---

## Debug 思路总结

这次问题最有价值的点不是单纯“禁用了几个任务”，而是形成一套通用的 Windows 自动启动问题排查思路：

```text
异常程序自动运行
        ↓
查看 ExecutablePath
        ↓
判断所属软件 / 驱动
        ↓
检查 Scheduled Task
        ↓
检查 Startup
        ↓
检查 Service
        ↓
必要时追踪 ParentProcessId
        ↓
找到真正触发源
        ↓
禁用 / 修复触发源
```

核心原则：

> 不要直接删除异常程序，优先找到“是谁启动了它”。

---

## 最终结果

本次通过禁用 AMD 相关计划任务并重启电脑后，`amdafdapp.exe` 自动弹窗问题不再复现。

状态：

```text
Resolved
```
