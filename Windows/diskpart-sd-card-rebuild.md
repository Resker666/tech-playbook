# 使用 DiskPart 重建 SD 卡分区并格式化

> 适用场景：Windows 下 SD 卡、U 盘分区异常，或需要按设备要求重新建立单个 FAT32 分区。操作会删除目标磁盘的分区信息，务必先备份数据并核对设备编号。

## 1. 操作前的重要提醒

**高风险：`clean` 会清除所选磁盘的分区结构，使原有分区与文件无法正常访问。它不是安全擦除命令，也不保证底层数据被覆盖。**

- **切勿机械照抄 `select disk 1`**：磁盘号因电脑、读卡器、连接顺序而变化。
- 先备份 SD 卡内重要数据。最好暂时拔掉其他不相关的 U 盘、移动硬盘。
- 必须用 **管理员权限** 打开 CMD 或 PowerShell。
- 通过 `list disk` 的**容量**与 `detail disk` 的**型号/连接信息**共同核实目标，不能仅凭磁盘号判断。
- `assign letter=E` 仅在 E: 未被占用时适用；不要求固定盘符时可以直接用 `assign`。
- **FAT32 不一定适合所有卡/设备**：大容量 SDXC 卡常用 exFAT，Windows 不同版本/格式化工具对大容量 FAT32 的创建能力也可能有限；应按目标设备实际支持的文件系统选择。
- 本文的 **MBR + FAT32** 是一种特定重建方案，不代表 SD 卡必须全部使用此组合。

## 2. 先识别目标磁盘（暂不清空）

在管理员 CMD 或 PowerShell 中启动：

```bat
diskpart
list disk
```

找到疑似 SD 卡的磁盘号，再执行（以下 **1 只是示例**，必须替换为实际磁盘号）：

```bat
select disk 1
detail disk
list partition
```

**在此处暂停并核实：**

1. `detail disk` 显示的容量、设备型号、连接方式是否符合 SD 卡？
2. `list partition` 看到的现有分区是否确实属于要清空的卡？
3. 是否确定目标不是 Windows 系统盘或其他存有资料的硬盘？

如果有任何疑问，**不要运行 `clean`**。可以先退出 DiskPart，重新插拔 SD 卡对照 `list disk` 变化。

## 3. 清空并重建分区（破坏性操作）

仅当上一步确认目标磁盘完全正确，且数据已备份，才继续：

```bat
clean
convert mbr
create partition primary
select partition 1
format fs=fat32 quick
assign
```

说明：

| 命令 | 作用 |
| --- | --- |
| `clean` | 清除当前选中磁盘的分区信息；**不会安全擦除所有数据** |
| `convert mbr` | 选择 MBR 分区样式（一般要求磁盘不含分区） |
| `create partition primary` | 在可用空间创建主分区（未指定大小时通常使用可用空间） |
| `select partition 1` | 选中新建分区 |
| `format fs=fat32 quick` | 将所选卷快速格式化为 FAT32 |
| `assign` | 自动分配可用盘符 |

如果确实需要固定为 E:，且已确认 E: 未占用，可将最后一条替换成：

```bat
assign letter=E
```

**关于原始步骤中的 `select disk 1`：** 这只是演示。实际执行时，必须在第 2 步选中自己核实过的磁盘，并保持在同一个 DiskPart 会话中；如果重新进入了 DiskPart，需要重新选择与确认。

> 如果 `convert mbr`、`format fs=fat32 quick` 等命令报错，不要在未知状态下反复执行 `clean`。先查看错误提示、容量、设备写保护状态、读卡器支持情况和目标设备的文件系统要求。

## 4. 检查重建结果

在 DiskPart 里运行：

```bat
list disk
list partition
list volume
detail disk
exit
```

一般期望看到：

- 目标磁盘可识别，容量与 SD 卡标称容量大致相符（显示单位换算可能有差异）。
- 已建立预期数量的分区（本方案通常是一个主分区）。
- `list volume` 中对应卷显示为 **FAT32**，并已分配盘符。
- 文件管理器可以打开此卷，且能正常进行读写测试。

验证时也可以在 PowerShell 查看卷信息（将 E 换成实际盘符）：

```powershell
Get-Volume -DriveLetter E
```

若卡是为 IPC / 嵌入式设备准备的，还应将其插入**实际目标设备**检查识别、挂载、读写和录制是否正常。Windows 能访问不代表固件必然支持。

## 5. 常见问题

### 5.1 `format fs=fat32 quick` 失败

可能与分区容量、Windows 版本/工具的格式化限制、设备读写故障等有关。先看准确错误信息，再决定是否调整分区大小或改用目标设备支持的文件系统；不要仅为了“成功格式化”擅自改变设备要求。

### 5.2 `assign letter=E` 失败

E: 可能已经被使用。可以先执行 `list volume` 查看，然后改用 `assign` 自动分配。不要强行占用现有盘符。

### 5.3 SD 卡只读、I/O 错误或经常掉盘

先检查 SD 卡适配器写保护拨片、读卡器、接口及卡本身的健康状况。软件重建分区不一定能修复硬件故障。

### 5.4 格式化成功但设备不识别

核对目标设备要求：容量上限、FAT32/exFAT、MBR/GPT、分区数量、簇大小及固件支持。不要默认所有 SD 卡都必须 FAT32。

## 6. 操作命令速查

以下命令保留最初的操作顺序，**只作为核对清单，不能在未核对磁盘号的情况下整段照抄执行**。

```bat
diskpart
list disk
select disk 1
detail disk
clean
convert mbr
create partition primary
select partition 1
format fs=fat32 quick
assign letter=E
list partition
list volume
detail disk
exit
```

- `disk 1` 仅为示例；必须使用本机正确磁盘号。
- `letter=E` 仅为示例；必须确认盘符可用，否则用 `assign`。
- **最重要的停顿点：执行 `clean` 之前，再次确认 `detail disk`。**

## 参考资料

- [Microsoft Learn — diskpart](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart)
- [Microsoft Learn — clean](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/clean)
- [Microsoft Learn — format](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/format)

---

> 分类：Windows / DiskPart / SD Card / Partition / FAT32。本文仅为通用操作记录，具体文件系统和分区方案以目标设备规范为准。
