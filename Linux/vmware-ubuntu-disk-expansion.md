# VMware Ubuntu 虚拟机磁盘扩容

## 背景

Ubuntu 虚拟机根分区空间耗尽：

```text
/dev/sda3        64G   61G  7.4M  100% /
```

在 VMware 中把虚拟磁盘扩展到 85G 后，Ubuntu 并不会自动使用新增空间，还需要扩展 Linux 分区和文件系统。

## 1. 查看磁盘与分区

```bash
df -h
lsblk
```

本次扩容前：

```text
sda      8:0    0    85G  0 disk
├─sda1   8:1    0     1M  0 part
├─sda2   8:2    0   513M  0 part /boot/efi
└─sda3   8:3    0  64.5G  0 part /
```

可以判断：

- VMware 虚拟磁盘 `/dev/sda` 已经扩展到 85G。
- 根分区 `/dev/sda3` 仍只有约 64.5G。
- 新增空间还没有分配给根分区。

因此需要先扩分区，再扩文件系统。

## 2. 扩展分区

```bash
sudo growpart /dev/sda 3
```

本次输出：

```text
CHANGED: partition=3 start=1054720 old: size=135260127 end=136314847 new: size=177203167 end=178257887
```

看到 `CHANGED` 表示第 3 个分区已经成功扩展。

其中：

- `/dev/sda`：目标磁盘。
- `3`：第 3 个分区，即 `/dev/sda3`。

此时只是分区变大，文件系统还没有使用新增空间。

## 3. 扩展 ext4 文件系统

本机根分区使用 ext4：

```bash
sudo resize2fs /dev/sda3
```

本次输出：

```text
resize2fs 1.46.5 (30-Dec-2021)
/dev/sda3 上的文件系统已被挂载于 /；需要进行在线调整大小
old_desc_blocks = 9, new_desc_blocks = 11
/dev/sda3 上的文件系统大小已经调整为 22150395 个块（每块 4k）。
```

“在线调整大小”是正常现象。ext4 支持在挂载状态下扩容，因此根分区通常无需卸载或重启。

## 4. 验证扩容

```bash
df -h
```

扩容后：

```text
/dev/sda3        83G   61G   19G   77% /
```

说明扩容成功。

`lsblk` 中磁盘显示约 85G，而 `df -h` 中文件系统约 83G 属于正常现象，与分区、文件系统元数据以及容量显示方式有关。

## 5. 完整流程速记

```text
VMware 中扩大虚拟硬盘
        ↓
lsblk 确认磁盘容量已经变大
        ↓
growpart 扩大 Linux 分区
        ↓
resize2fs 扩大 ext4 文件系统
        ↓
df -h 验证
```

本机对应命令：

```bash
lsblk
sudo growpart /dev/sda 3
sudo resize2fs /dev/sda3
df -h
```

## 6. 如何判断卡在哪一层

### sda 没有变大

如果 `lsblk` 中整个 `sda` 仍然是旧容量，说明 VMware 虚拟硬盘没有成功扩容，应先检查 VMware 的虚拟硬盘 Expand 设置。

### sda 变大，但 sda3 没变

例如：

```text
sda     85G
sda3  64.5G
```

说明虚拟硬盘已经变大，但 Linux 分区尚未扩展：

```bash
sudo growpart /dev/sda 3
```

### sda3 变大，但 df -h 还是旧容量

说明分区已经扩大，但文件系统还没有扩大。

ext4：

```bash
sudo resize2fs /dev/sda3
```

XFS 通常使用：

```bash
sudo xfs_growfs /
```

可以先确认文件系统类型：

```bash
df -T /
```

## 7. 常见问题

### growpart 提示 NOCHANGE

可能原因：

- VMware 磁盘实际上没有扩容成功。
- 目标分区后面存在其他分区。
- 当前分区已经占满整个磁盘。

检查：

```bash
lsblk
sudo fdisk -l
```

### resize2fs 不适用

`resize2fs` 用于 ext2/ext3/ext4。先执行：

```bash
df -T /
```

确认文件系统类型。

### 使用 LVM

如果 `lsblk` 中出现 `lvm`，不能直接照搬本文流程。LVM 通常还涉及：

```text
growpart
→ pvresize
→ lvextend
→ resize2fs / xfs_growfs
```

应根据实际 VG/LV 结构处理。

## 8. 磁盘增长过快时排查

如果虚拟机经常需要扩容，不应只反复增加容量，还应该定位空间占用来源。

查看根目录一级占用：

```bash
sudo du -xh --max-depth=1 / 2>/dev/null | sort -h
```

查看 `/home`：

```bash
du -xh --max-depth=1 /home 2>/dev/null | sort -h
```

查看当前开发用户目录：

```bash
du -xh --max-depth=1 /home/daq 2>/dev/null | sort -h
```

查找大于 1G 的文件：

```bash
sudo find / -xdev -type f -size +1G -exec ls -lh {} \; 2>/dev/null
```

开发环境中常见的大空间来源：

- 编译输出目录
- SDK / Toolchain
- Git 仓库中的大对象
- Docker 镜像
- 下载和软件包缓存
- 日志
- core dump
- Snap 旧版本

## 9. 本次实际结果

扩容前：

```text
/dev/sda3  64G  61G  7.4M  100% /
```

VMware 虚拟磁盘：

```text
/dev/sda   85G
```

执行：

```bash
sudo growpart /dev/sda 3
sudo resize2fs /dev/sda3
```

扩容后：

```text
/dev/sda3  83G  61G  19G  77% /
```

## 一句话记忆

> VMware 扩盘后，Ubuntu 不会自动使用新增容量。对于普通 ext4 分区，通常需要先用 `growpart` 扩分区，再用 `resize2fs` 扩文件系统。
