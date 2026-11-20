# VMware Workstation 提示虚拟机正在使用，获取所有权失败

## 现象

Windows 重启后，VMware Workstation Pro 17 打开本地 Ubuntu 虚拟机时提示「该虚拟机似乎正在使用中」。点击「获取所有权」后又提示「获取该虚拟机的所有权失败」，并询问是否从库中移除虚拟机。

这个提示出现在 Ubuntu 启动前。先区分 Windows 上是否还有程序在使用虚拟机文件，以及是否只有 VMware 上次遗留的 `.lck` 锁。仅凭提示不能认定虚拟硬盘损坏。

## 快速处理

1. 如果是第一次看到提示，而且确认没有其他实例在运行这台虚拟机，可以先点「获取所有权」。如果已经失败，在第二个弹窗点「取消」。「移除」只会把虚拟机从 Workstation 列表移掉，不能解除占用。
2. 退出 VMware Workstation。按 `Ctrl + Shift + Esc` 打开任务管理器，在「详细信息」中查看 `vmware-vmx.exe`。如果仍有这个进程，先确认它是否属于这台虚拟机，不要直接结束其他虚拟机的进程。
3. 确认目标虚拟机已关机、文件不再被进程使用后，打开弹窗所指向的 `.vmx` 所在目录。若有以 `.lck` 结尾的文件或文件夹，先移到其他位置备份。双击原目录里的 `.vmx`，启动虚拟机。只移动 `.lck`，不动 `.vmx` 配置、`.vmdk` 虚拟磁盘或 `.vmss` 挂起状态文件。
4. 如果找不到 `.lck`、移动时提示文件被占用，或无法确认进程对应哪台虚拟机，按 `Win + R` 输入 `resmon`。在「CPU → 关联的句柄」搜索虚拟机目录名或 `.vmx` 文件名，根据结果确认是谁在占用，再正常退出对应程序。

## 重启与验证

再重启 Windows 可能释放进程持有的文件句柄，但不会保证清掉已经留在磁盘上的 `.lck`。已经重启过一次并看到同样的提示时，优先按上述步骤排查。

确认虚拟机能重新打开并进入 Ubuntu 后，可以删除移出的旧 `.lck` 备份，不用放回原目录。本次故障已恢复，但没有记录最终是哪一步解除占用，不能据此确定根因。

## 参考

- [Broadcom Workstation 启动报错知识库](https://knowledge.broadcom.com/external/article/329349)（也列出相同的占用提示。该文处理的是挂起状态损坏，这里不需要照做其清除挂起状态的步骤。）
- [Microsoft 如何查找占用文件的进程](https://techcommunity.microsoft.com/blog/itopstalkblog/identify-which-process-is-blocking-a-file-in-windows/4432635/)
